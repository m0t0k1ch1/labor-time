use File::Spec;
use File::Basename qw(dirname);
my $basedir = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $dbpath = File::Spec->catfile($basedir, 'db', 'deployment.db');
+{
    DBI => [
        'dbi:mysql:database=labor-time',
        'piyo',
        'poyo',
        { mysql_enable_utf8 => 1 },
    ],
    moves => {
        client_id             => 'your client id',
        client_secret         => 'your client secret',
        site                  => 'https://api.moves-app.com',
        authorize_path_for_sp => 'moves://app/authorize',
        authorize_path_for_pc => 'https://api.moves-app.com/oauth/v1/authorize',
        access_token_path     => 'https://api.moves-app.com/oauth/v1/access_token',
    },
};
