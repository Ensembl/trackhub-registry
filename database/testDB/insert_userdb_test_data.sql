INSERT INTO users (username, password, first_name, last_name, email_address, affiliation, active) VALUES (
    'admin', 'dummy', 'Admin', 'Admin','prem@ebi.ac.uk', 'EMBL-EBI', 'Y'
);

INSERT INTO users (username, password, first_name, last_name, email_address, affiliation, active) VALUES (
    'trackhub1', 'trackhub1', 'Track', 'Hub1','trackhub1@ebi.ac.uk','EMBL-EBI', 'Y'
);
INSERT INTO users (username, password, first_name, last_name, email_address, affiliation, active) VALUES (
    'trackhub2', 'trackhub2', 'Track', 'Hub2','trackhub2@ebi.ac.uk','EMBL-EBI', 'Y'
);
INSERT INTO users (username, password, first_name, last_name, email_address, affiliation, active) VALUES (
    'trackhub3', 'trackhub3', 'Track', 'Hub3','trackhub3@ebi.ac.uk','EMBL-EBI', 'Y'
);
INSERT INTO users (username, password, first_name, last_name, email_address, affiliation, active) VALUES (
    'test01', 'test01', 'Test', '01','test01@ebi.ac.uk','EMBL-EBI', 'Y'
);
INSERT INTO users (username, password, first_name, last_name, email_address, affiliation, active) VALUES (
    'test02', 'test02', 'Test', '01','test01@ebi.ac.uk','EMBL-EBI', 'Y'
);


INSERT INTO roles (name) VALUES ('admin');
INSERT INTO roles (name) VALUES ('user');

INSERT INTO user_roles (user_id, role_id) VALUES (
    (SELECT id FROM users WHERE username = 'admin'),
    (SELECT id FROM roles WHERE name     = 'admin')
);

INSERT INTO user_roles (user_id, role_id) VALUES (
    (SELECT id FROM users WHERE username = 'trackhub1'),
    (SELECT id FROM roles WHERE name     = 'user')
);

INSERT INTO user_roles (user_id, role_id) VALUES (
    (SELECT id FROM users WHERE username = 'trackhub2'),
    (SELECT id FROM roles WHERE name     = 'user')
);

INSERT INTO user_roles (user_id, role_id) VALUES (
    (SELECT id FROM users WHERE username = 'trackhub3'),
    (SELECT id FROM roles WHERE name     = 'user')
);

INSERT INTO user_roles (user_id, role_id) VALUES (
    (SELECT id FROM users WHERE username = 'test01'),
    (SELECT id FROM roles WHERE name     = 'user')
);

INSERT INTO user_roles (user_id, role_id) VALUES (
    (SELECT id FROM users WHERE username = 'test02'),
    (SELECT id FROM roles WHERE name     = 'user')
);





