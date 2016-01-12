use strict;
use warnings;

# use Registry;

# my $app = Registry->apply_default_middlewares(Registry->psgi_app);
# $app;

use Config;
use Registry;
use File::Basename;
use File::Spec;
use Plack::Builder;
use Plack::Util;

# use Plack::Middleware::EnsThrottle::MemcachedBackend;
# use Cache::Memcached;

my $app = Registry->psgi_app;

builder {

  #------ Set appropriate headers when we detect REST is being used as a ReverseProxy
  enable "Plack::Middleware::ReverseProxy";
  #------ Set Content-type headers when we detect a valid extension
  # this is not available any more
  # enable "DetectExtension";
  #------ Allow CrossOrigin requests from any host
  enable 'CrossOrigin', origins => '*', headers => '*', methods => ['GET','POST','DELETE','OPTIONS'];
  
  
  my $dirname = dirname(__FILE__);
  my $rootdir = File::Spec->rel2abs(File::Spec->catdir($dirname, File::Spec->updir(), File::Spec->updir()));
  my $staticdir = File::Spec->catdir($rootdir, 'root');

  #-------- RECOMMENDED PLUGINS -------- #

  #------ Reset processes if they get too big
  #if mac and SizeLimit is on then need to require this:
  Plack::Util::load_class('BSD::Resource') if $Config{osname} eq 'darwin';
  enable 'SizeLimit' => (
      max_unshared_size_in_kb => (300 * 1024),    # 300MB per process (memory assigned just to the process)
      # max_process_size_in_kb => (4096*25),  # seems to be the option which looks at overall size
      check_every_n_requests => 10,
  );

  #------ Adds a better stack trace
  enable 'StackTrace';

  #------ Adds a runtime header
  enable 'Runtime';

  #----- Enable compression on output
  enable sub {
    my $app = shift;
    sub {
      my $env = shift;
      my $ua = $env->{HTTP_USER_AGENT} || '';

      # Netscape has some problem
      $env->{"psgix.compress-only-text/html"} = 1 if $ua =~ m!^Mozilla/4!;

      # Netscape 4.06-4.08 have some more problems
      $env->{"psgix.no-compress"} = 1 if $ua =~ m!^Mozilla/4\.0[678]!;

      # MSIE (7|8) masquerades as Netscape, but it is fine
      if ( $ua =~ m!\bMSIE (?:7|8)! ) {
        $env->{"psgix.no-compress"}             = 0;
        $env->{"psgix.compress-only-text/html"} = 0;
      }
      $app->($env);
    }
  };
    
  #------ Plack to set ContentLength header
  enable "ContentLength";

  #------ Compress response body with gzip or deflate
  enable "Deflater",
    content_type =>
    [ 'text/css', 'text/html', 'text/javascript', 'application/javascript' ],
    vary_user_agent => 1;

  #----- Javascript & CSS minimisation and expire dates set
  # CSS assets are first
  enable "Assets", files => [<$staticdir/static/css/*.css>];

  # Javascript assets are second
  enable "Assets",
    files  => [<$staticdir/static/js/*.js>],
    type   => 'js',
    minify => 1;
   
  #----- Plack to serve static content - THIS MUST COME AFTER ASSETS GENERATION AS THEY HAVE FILE EXTENSIONS
  enable "Static",
    path => qr{\.(?:js|css|jpe?g|gif|ico|png|html?|swf|txt)$},
    root => $staticdir;

  #------ END OF PLUGINS -------#

  $app;
}

