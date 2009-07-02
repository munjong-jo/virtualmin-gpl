
# script_django_desc()
sub script_django_desc
{
return "Django";
}

sub script_django_uses
{
return ( "python" );
}

sub script_django_longdesc
{
return "Django is a high-level Python Web framework that encourages rapid development and clean, pragmatic design.";
}

# script_django_versions()
sub script_django_versions
{
return ( "1.0.2" );
}

sub script_django_category
{
return "Development";
}

sub script_django_python_modules
{
local ($d, $ver, $opts) = @_;
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
return ( "setuptools", $dbtype eq "mysql" ? "MySQLdb" : "psycopg" );
}

# script_django_depends(&domain, version)
# Check for ruby command, ruby gems, mod_proxy
sub script_django_depends
{
local ($d, $ver) = @_;
local @rv;
&has_command("python") || push(@rv, "The python command is not installed");
&require_apache();
local $conf = &apache::get_config();
local $got_rewrite;
foreach my $l (&apache::find_directive("LoadModule", $conf)) {
	$got_rewrite++ if ($l =~ /mod_rewrite/);
	}
$apache::httpd_modules{'mod_fcgid'} ||
	push(@rv, "Apache does not have the mod_fcgid module");
$apache::httpd_modules{'mod_rewrite'} || $got_rewrite ||
	push(@rv, "Apache does not have the mod_rewrite module");
return @rv;
}

# script_django_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_django_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Django database", $dbname);
	$rv .= &ui_table_row("Initial project name",
		$upgrade->{'opts'}->{'project'});
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Django database",
		     &ui_database_select("db", undef, \@dbs, $d, "django"));
	$rv .= &ui_table_row("Initial project name",
		     &ui_textbox("project", "myproject", 30));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", undef, 30,
					     "At top level"));
	$rv .= &ui_table_row("",
	    "Warning - Django works best when installed at the top level.");
	}
return $rv;
}

# script_django_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_django_parse
{
local ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	local $hdir = &public_html_dir($d, 0);
	$in->{'dir_def'} || $in->{'dir'} =~ /\S/ && $in->{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	local $dir = $in->{'dir_def'} ? $hdir : "$hdir/$in->{'dir'}";
	$in{'project'} =~ /^[a-z0-9]+$/ ||
		return "Project name can only contain letters and numbers";
	local ($newdb) = ($in->{'db'} =~ s/^\*//);
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
		 'dir' => $dir,
		 'path' => $in->{'dir_def'} ? "/" : "/$in->{'dir'}",
		 'project' => $in{'project'} };
	}
}

# script_django_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_django_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/django.fcgi") {
	return "Django appears to be already installed in the selected directory";
	}
$opts->{'project'} ||
	return "Missing initial project name";
$opts->{'project'} =~ /^[a-z0-9]+$/ ||
	return "Project name can only contain letters and numbers";
return undef;
}

# script_django_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by Rails, each of which is a hash ref
# containing a name, filename and URL
sub script_django_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = (
	 { 'name' => "source",
	   'file' => "Django-$ver-final.tar.gz",
	   'url' => "http://www.djangoproject.com/download/$ver/tarball/" },
	 { 'name' => "flup",
	   'file' => "flup-1.0.tar.gz",
	   'url' => "http://www.saddi.com/software/flup/dist/flup-1.0.tar.gz" },
	);
return @files;
}

sub script_django_commands
{
local ($d, $ver, $opts) = @_;
return ("python");
}

# script_django_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs PhpWiki, and returns either 1 and an informational
# message, or 0 and an error
sub script_django_install
{
local ($d, $version, $opts, $files, $upgrade, $domuser, $dompass) = @_;
local ($out, $ex);

# Get database settings
if ($opts->{'newdb'} && !$upgrade) {
	local $err = &create_script_database($d, $opts->{'db'});
	return (0, "Database creation failed : $err") if ($err);
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
local $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
local $dbhost = &get_database_host($dbtype);
$dbhost = undef if ($dbhost eq "localhost" || $dbhost eq "127.0.0.1");
if ($dbtype) {
	local $dberr = &check_script_db_connection($dbtype, $dbname,
						   $dbuser, $dbpass);
	return (0, "Database connection failed : $dberr") if ($dberr);
	}
local $python = &has_command("python");

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
		return (0, "Failed to create directory : <tt>$out</tt>.");
	}

# Create python base dir
$ENV{'PYTHONPATH'} = "$opts->{'dir'}/lib/python";
&run_as_domain_user($d, "mkdir -p ".quotemeta($ENV{'PYTHONPATH'}));

# Extract the source, then install to the target dir
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d);
$err && return (0, "Failed to extract Django source : $err");
local $icmd = "(cd ".quotemeta("$temp/Django-$ver-final")." && ".
      "python setup.py install --home ".quotemeta($opts->{'dir'}).") 2>&1";
local $out = &run_as_domain_user($d, $icmd);
if ($?) {
	return (0, "Django source install failed : ".
		   "<pre>".&html_escape($out)."</pre>");
	}

# Extract and copy the flup source
local $err = &extract_script_archive($files->{'flup'}, $temp, $d);
$err && return (0, "Failed to extract flup source : $err");
local $out = &run_as_domain_user($d, 
	"cp -r ".quotemeta("$temp/flup-1.0/flup").
	" ".quotemeta("$opts->{'dir'}/lib/python"));
if ($?) {
	return (0, "flup source copy failed : ".
		   "<pre>".&html_escape($out)."</pre>");
	}

if (!$upgrade) {
	# Create the initial project
	local $icmd = "cd ".quotemeta($opts->{'dir'})." && ".
		      "./bin/django-admin.py startproject ".
		      quotemeta($opts->{'project'})." 2>&1";
	local $out = &run_as_domain_user($d, $icmd);
	if ($?) {
		return (0, "Project initialization install failed : ".
			   "<pre>".&html_escape($out)."</pre>");
		}

	# Fixup settings.py to use the MySQL DB
	local $pdir = "$opts->{'dir'}/$opts->{'project'}";
	local $sfile = "$pdir/settings.py";
	-r $sfile || return (0, "Project settings file $sfile was not found");
	local $lref = &read_file_lines_as_domain_user($d, $sfile);
	my $i = 0;
	foreach my $l (@$lref) {
		if ($l =~ /DATABASE_ENGINE\s*=/) {
			if ($dbtype eq "mysql") {
				$l = "DATABASE_ENGINE = 'mysql'";
				}
			else {
				$l = "DATABASE_ENGINE = 'postgresql'";
				}
			}
		if ($l =~ /DATABASE_NAME\s*=/) {
			$l = "DATABASE_NAME = '$dbname'";
			}
		if ($l =~ /DATABASE_USER\s*=/) {
			$l = "DATABASE_USER = '$dbuser'";
			}
		if ($l =~ /DATABASE_PASSWORD\s*=/) {
			$l = "DATABASE_PASSWORD = '".
			     &php_quotemeta($dbpass)."'";
			}
		if ($l =~ /DATABASE_HOST\s*=/) {
			$l = "DATABASE_HOST = '$dbhost'";
			}
		if ($l =~ /INSTALLED_APPS\s*=\s*\(/) {
			splice(@$lref, $i+1, 0,
			       "    'django.contrib.admin',");
			}
		$i++;
		}
	&flush_file_lines_as_domain_user($d, $sfile);

	# Activate the admin site
	local $ufile = "$pdir/urls.py";
	local $lref = &read_file_lines_as_domain_user($d, $ufile);
	foreach my $l (@$lref) {
		if ($l =~ /^(\s*)#(.*django.contrib.admin.urls.*)/ ||
		    $l =~ /^(\s*)#(.*admin.site.root.*)/) {
			# Un-comment /admin/ path
			$l = $1.$2;
			}
		elsif ($l =~ /^\s*#\s*(from django.contrib import admin)/ ||
		       $l =~ /^\s*#\s*(admin.autodiscover\(\))/) {
			# Un-comment admin includes
			$l = $1;
			}
		}
	&flush_file_lines_as_domain_user($d, $ufile);

	# Initialize the DB
	# Input is 'yes', username, email, password, password again
	local $icmd = &command_as_user($d->{'user'}, 0,
				       "$python manage.py syncdb");
	local $pwd = &get_current_dir();
	&foreign_require("proc", "proc-lib.pl");
	chdir($pdir);
	local ($fh, $fpid) = &proc::pty_process_exec($icmd);
	chdir($pwd);
	local $out;
	foreach my $w ([ "yes.no", "yes" ],
		       [ "Username", $domuser ],
		       [ "E-mail address", $d->{'emailto'} ],
		       [ "Password", $dompass ],
		       [ "Password", $dompass ]) {
		local $rv = &wait_for($fh, $w->[0]);
		if ($rv < 0) {
			return (0,
			   "Database initialization failed at $w->[0] : ".
			   "<pre>".&html_escape($wait_for_input)."</pre>");
			}
		&sysprint($fh, $w->[1]."\n");
		$out .= $wait_for_input;
		}
	&wait_for($fh, 'EOF');		# Wait till done
	close($fh);
	waitpid($fpid, 0);
	local $ex = $?;
	if ($ex || $out =~ /error/i) {
		return (0, "Database initialization failed : ".
			   "<pre>".&html_escape($out)."</pre>");
		}
	}

# Create python fcgi wrapper script
local $wrapper = "$opts->{'dir'}/django.fcgi";
if (!-r $wrapper) {
	&open_tempfile_as_domain_user($d, WRAPPER, ">$wrapper");
	&print_tempfile(WRAPPER, "#!$python\n");
	&print_tempfile(WRAPPER, "import sys, os\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}/lib/python\")\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}\")\n");
	&print_tempfile(WRAPPER, "os.chdir(\"$opts->{'dir'}\")\n");
	&print_tempfile(WRAPPER, "os.environ['DJANGO_SETTINGS_MODULE'] = \"$opts->{'project'}.settings\"\n");
	&print_tempfile(WRAPPER, "from django.core.servers.fastcgi import runfastcgi\n");
	&print_tempfile(WRAPPER, "runfastcgi(method=\"threaded\", daemonize=\"false\")\n");
	&close_tempfile_as_domain_user($d, WRAPPER);
	&set_permissions_as_domain_user($d, 0755, $wrapper);
	}

# Add <Location> block to Apache config
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @locs = &apache::find_directive_struct("Location", $vconf);
	local ($loc) = grep { $_->{'words'}->[0] eq $opts->{'path'} } @locs;
	next if ($loc);
	local $reldir = $opts->{'dir'};
	$reldir =~ s/^\Q$d->{'home'}\/\E//;
	local $loc = { 'name' => 'Location',
		       'value' => $opts->{'path'},
		       'type' => 1,
		       'members' => [
			{ 'name' => 'AddHandler',
			  'value' => 'fcgid-script .fcgi' },
			{ 'name' => 'RewriteEngine',
			  'value' => 'On' },
			{ 'name' => 'RewriteCond',
			  'value' =>
				'%{REQUEST_FILENAME} !django.fcgi|/media/' },
			{ 'name' => 'RewriteRule',
			  'value' => "$reldir(.*) django.fcgi/\$1 [L]" },
			]
		     };
	&apache::save_directive_struct(undef, $loc, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

# All /media alias to Apache config
local $mpath = $opts->{'path'} eq '/' ? "/media/"
				      : "$opts->{'path'}/media/";
local $mdir = "$opts->{'dir'}/lib/python/django/contrib/admin/media/";
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @al = &apache::find_directive("Alias", $vconf);
	local ($media) = grep { $_ =~ /^\Q$mpath\E\s/ } @al;
	next if ($media);
	push(@al, "$mpath $mdir");
	&apache::save_directive("Alias", \@al, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

&register_post_action(\&restart_apache);

local $url = &script_path_url($d, $opts);
local $adminurl = $url."admin/";
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "Initial Django installation complete. Go to <a target=_new href='$adminurl'>$adminurl</a> to manage it. Django is a development environment, so it doesn't do anything by itself!", "Under $rp", $url, $domuser, $dompass);
}

# script_django_uninstall(&domain, version, &opts)
# Un-installs a Rails installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_django_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Remove base Django tables from the database
&cleanup_script_database($d, $opts->{'db'}, "(django|auth)_");

# Remove <Location> block
&require_apache();
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @locs = &apache::find_directive_struct("Location", $vconf);
	local ($loc) = grep { $_->{'words'}->[0] eq $opts->{'path'} } @locs;
	next if (!$loc);
	&apache::save_directive_struct($loc, undef, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

# Media /media lias
local $mpath = $opts->{'path'} eq '/' ? "/media/"
				      : "$opts->{'path'}/media/";
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @al = &apache::find_directive("Alias", $vconf);
	local ($media) = grep { $_ =~ /^\Q$mpath\E\s/ } @al;
	next if (!$media);
	@al = grep { $_ ne $media } @al;
	&apache::save_directive("Alias", \@al, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

&register_post_action(\&restart_apache);

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

return (1, "Django directory and tables deleted.");
}

# script_django_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_django_latest
{
local ($ver) = @_;
return ( "http://www.djangoproject.com/download/",
	 "Django-([0-9\\.]+)-final.tar.gz" );
}

sub script_django_site
{
return 'http://www.djangoproject.com/';
}

sub script_django_passmode
{
return 1;
}

1;

