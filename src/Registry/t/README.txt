# Testing the Trackhub Registry #

Many tests here require an Elasticsearch instance (version 6+) running in the background. Great effort has been put into making tests stand-alone using Search::Elasticsearch::Test, but it has proven very difficult to get Elasticsearch to start on demand on a Travis server. The inability to live debug a session makes the process frustrating at best.

On linux, Elasticsearch can be installed trivially via .deb or .rpm packages. Mac OS developers have to work harder to get the server working, as it has to be run manually.