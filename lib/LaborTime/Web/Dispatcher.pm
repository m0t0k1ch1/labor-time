package LaborTime::Web::Dispatcher;

use strict;
use warnings;
use utf8;

use Amon2::Web::Dispatcher::Lite;

use DateTime;
use DateTime::Format::HTTP;
use Geo::Coder::Google::V3;
use JSON;
use Net::OAuth2::Profile::WebServer;

our $MOVES_CALLBACK_PATH = '/callback';

get '/' => sub {
    my $c = shift;

    if ($c->session->get('access_token')) {
        my $workplace = select_user_workplace($c, user_id($c));
        my $work_logs;
        if ($workplace) {
            $work_logs = work_logs($c, $workplace->{workplace_id});
        }

        my %stash;
        $stash{workplace} = $workplace;
        $stash{work_logs} = $work_logs;

        return $c->render('index.tt', \%stash);
    }
    else {
        my $scope;
        if ($c->req->header('User-Agent') =~ /iPhone/) {
            $scope = ['activity', 'location'];
        } else {
            $scope = 'activity location';
        }

        my %stash;
        $stash{moves_authorize_uri} = client($c)->authorize(
            redirect_uri => redirect_uri($c),
            scope        => $scope,
        );

        return $c->render('signin.tt', \%stash);
    }
};

get '/profile' => sub {
    my $c = shift;

    my $res = access_token($c)->get('/api/v1/user/profile');

    my $workplace      = select_user_workplace($c, user_id($c));
    my $regular_places = regular_places($c);

    my %stash;
    $stash{profile}        = decode_json($res->content);
    $stash{workplace}      = $workplace;
    $stash{regular_places} = $regular_places;

    return $c->render('profile.tt', \%stash);
};

get '/how_to' => sub {
    my $c = shift;

    return $c->render('how_to.tt');
};

get $MOVES_CALLBACK_PATH => sub {
    my $c = shift;

    if ($c->req->param('error')) {
        $c->redirect('/');
    } else {
        $c->session->set(access_token => access_token($c)->session_freeze);
        $c->redirect('/');
    }
};

get '/logout' => sub {
    my $c = shift;

    $c->session->set(access_token => undef);
    $c->redirect('/');
};

post '/set_workplace' => sub {
    my $c = shift;

    my $user_id           = user_id($c);
    my $workplace_id      = $c->req->param('workplace_id');
    my $workplace_address = $c->req->param('workplace_address');

    insert_or_update_user_workplace($c, $user_id, $workplace_id, $workplace_address);

    $c->redirect('/');
};

sub redirect_uri {
    my $c = shift;

    my $uri = $c->req->uri;
    $uri->path($MOVES_CALLBACK_PATH);
    $uri->query_form({});

    return $uri;
}

sub client {
    my $c = shift;

    my $config = $c->config->{moves};

    if ($c->req->header('User-Agent') =~ /iPhone/) {
        $config->{authorize_path} = $config->{authorize_path_for_sp};
    } else {
        $config->{authorize_path} = $config->{authorize_path_for_pc};
    }

    return Net::OAuth2::Profile::WebServer->new(%{ $config });
}

sub access_token {
    my $c = shift;

    my $access_token = $c->session->get('access_token');
    if (defined $access_token) {
        return Net::OAuth2::AccessToken->session_thaw(
            $access_token,
            profile => client($c),
        );
    } else {
        return client($c)->get_access_token(
            $c->req->param('code'),
            redirect_uri => redirect_uri($c),
        );
    }
}

sub user_id {
    my $c = shift;

    my $res     = access_token($c)->get('/api/v1/user/profile');
    my $profile = decode_json($res->content);

    return $profile->{userId};
}

sub insert_or_update_user_workplace {
    my ($c, $user_id, $workplace_id, $workplace_address) = @_;

    if (select_user_workplace($c, $user_id)) {
        update_user_workplace($c, $user_id, $workplace_id, $workplace_address);
    } else {
        insert_user_workplace($c, $user_id, $workplace_id, $workplace_address);
    }
}

sub select_user_workplace {
    my ($c, $user_id) = @_;

    my $sql = 'SELECT * FROM user_workplace WHERE user_id = ?';
    my $sth = $c->dbh->prepare($sql);

    $sth->execute($user_id);

    return $sth->fetchrow_hashref;
}

sub insert_user_workplace {
    my ($c, $user_id, $workplace_id, $workplace_address) = @_;

    my $sql = 'INSERT INTO user_workplace (user_id, workplace_id, workplace_address) VALUES (?, ?, ?)';
    my $sth = $c->dbh->prepare($sql);

    $sth->execute($user_id, $workplace_id, $workplace_address);
}

sub update_user_workplace {
    my ($c, $user_id, $workplace_id, $workplace_address) = @_;

    my $sql = 'UPDATE user_workplace SET workplace_id = ?, workplace_address = ? WHERE user_id = ?';
    my $sth = $c->dbh->prepare($sql);

    $sth->execute($workplace_id, $workplace_address, $user_id);
}

sub regular_places {
    my $c = shift;

    my $days    = 7;
    my $res     = access_token($c)->get("/api/v1/user/places/daily?pastDays=${days}");
    my $results = decode_json($res->content);

    my $geocoder = Geo::Coder::Google::V3->new(apiver => 3, language => 'ja');

    my %place_id_counter;
    my @places;
    for my $result (@{ $results }) {
        for my $segment (@{ $result->{segments} }) {
            my $place_id = $segment->{place}->{id};
            $place_id_counter{$place_id}++;

            if ($place_id_counter{$place_id} == 2) {
                my $lat     = $segment->{place}->{location}->{lat};
                my $lon     = $segment->{place}->{location}->{lon};
                my $address = $geocoder->reverse_geocode(latlng => "${lat},${lon}");

                push @places, {
                    id      => $segment->{place}->{id},
                    address => $address->{formatted_address},
                };
            }
        }
    }

    return \@places;
}

sub work_logs {
    my ($c, $workplace_id) = @_;

    my $now = DateTime->now(time_zone => 'local');

    my @work_logs;
    for my $i (reverse 0..3) {
        my $ymd_from = $now->clone->subtract(days => 7 * ($i + 1))->ymd;
        my $ymd_to   = $now->clone->subtract(days => (7 * $i) + 1)->ymd;

        my $res     = access_token($c)->get("/api/v1/user/places/daily?from=${ymd_from}&to=${ymd_to}");
        my $results = decode_json($res->content);

        for my $result (@{ $results }) {
            my %work_log;
            $work_log{date} = $result->{date};

            my @time_logs;
            for my $segment (@{ $result->{segments} }) {
                if ($segment->{place}->{id} == $workplace_id) {
                    my $start_time = $DateTime::Format::HTTP->parse_datetime($segment->{startTime});
                    my $end_time   = $DateTime::Format::HTTP->parse_datetime($segment->{endTime});
                    push @time_logs, {
                        start_time => $start_time->add(hours => 9)->hms,
                        end_time   => $end_time->add(hours => 9)->hms,
                    };
                }
            }
            $work_log{time_logs} = \@time_logs;

            push @work_logs, \%work_log;
        }
    }

    @work_logs = reverse @work_logs;

    return \@work_logs;
}

1;
