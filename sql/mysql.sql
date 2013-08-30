CREATE TABLE IF NOT EXISTS sessions (
    id           CHAR(72) PRIMARY KEY,
    session_data TEXT
);

CREATE TABLE IF NOT EXISTS user_workplace (
    id                INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    user_id           BIGINT NOT NULL,
    workplace_id      INT NOT NULL,
    workplace_address TEXT NOT NULL
);
