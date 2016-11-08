DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS user_roles;
 
CREATE TABLE users (
    id 			INTEGER PRIMARY KEY AUTOINCREMENT,
    username 		TEXT NOT NULL UNIQUE,
    password 		TEXT NOT NULL,
    first_name 		TEXT NOT NULL,
    last_name		TEXT NOT NULL,
    email_address 	TEXT NOT NULL,
    affiliation		TEXT,
    password_expires TIMESTAMP,
    continuous_alert     INTEGER NOT NULL DEFAULT 0,
    check_interval      INTEGER NOT NULL DEFAULT 0,
    active 		CHAR(1) NOT NULL DEFAULT 'Y'
);
 
CREATE TABLE roles (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);
 
CREATE TABLE user_roles (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE user_tokens (
    username TEXT NOT NULL REFERENCES users(username) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
    auth_key TEXT NOT NULL,
    created_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (username, auth_key)
);
 
