sqlite3 registry.db < create_userdb_tables.sql
sqlite3 registry.db < insert_userdb_test_data.sql
./create_schema.sh 
perl set_admin_password.pl 
cp registry.db ../../src/Registry/t/
