#!/usr/local/bin/perl
# Actually create users

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&error_setup($text{'umass_err'});

# Validate source file
if ($in{'file_def'} == 1) {
	# Server-side file
	&master_admin() || &error($text{'cmass_elocal'});
	open(LOCAL, $in{'local'}) || &error($text{'cmass_elocal2'});
	while(<LOCAL>) {
		$source .= $_;
		}
	close(LOCAL);
	$src = "<tt>$in{'local'}</tt>";
	}
elsif ($in{'file_def'} == 0) {
	# Uploaded file
	$in{'upload'} =~ /\S/ || &error($text{'cmass_eupload'});
	$source = $in{'upload'};
	$src = $text{'cmass_uploaded'};
	}
elsif ($in{'file_def'} == 2) {
	# Pasted text
	$in{'text'} =~ /\S/ || &error($text{'cmass_etext'});
	$source = $in{'text'};
	$src = $text{'cmass_texted'};
	}
$source =~ s/\r//g;

# Do it!
&ui_print_header(&domain_in($d), $text{'umass_title'}, "", "umass");

print &text('umass_doing', $src),"<p>\n";

# Split into lines, and process each one
@lines = split(/\n+/, $source);
$lnum = 0;
$count = $ecount = 0;
USER: foreach $line (@lines) {
	$lnum++;
	next if ($line !~ /\S/);
	local ($username, $real, $pass, $ftp, $email, $quota, $extras, $forwards, $dbs) = split(/:/, $line, -1);
	$username = lc($username);
	$quota = &has_home_quotas() ? $quota : undef;
	local $mquota = &has_mail_quotas() ? $quota : undef;
	local $qquota = &has_server_quotas() ? $quota : undef;

	# Make sure needed parameters are given
	if (!$username) {
		&line_error($text{'umass_euname'});
		next USER;
		}
	if ($username !~ /^[^ \t:]+$/) {
		&line_error($text{'user_euser'});
		next USER;
		}
	if ($user->{'person'} && $real !~ /^[^:]*$/) {
		&line_error($text{'user_ereal'});
		next USER;
		}
	if ($quota !~ /^\d*$/) {
		&line_error($text{'umass_equota'});
		next USER;
		}
	if ($mquota !~ /^\d*$/) {
		&line_error($text{'umass_equota'});
		next USER;
		}

	# Check if this user has hit his mailbox limit
	local ($mleft, $mreason, $mmax) = &count_feature("mailboxes");
	if ($mleft == 0) {
		&line_error($text{'user_emailboxlimit'});
		next USER;
		}

	# Validate extra addresses
	local @extra = split(/,/, $extras);
	foreach $e (@extra) {
		if ($user->{'noextra'}) {
			&line_error($text{'umass_eextra'});
			next USER;
			}
		$e = lc($e);
		if ($e =~ /^([^\@ \t]+$)$/) {
			$e = "$e\@$d->{'dom'}";
			}
		if ($e !~ /^(\S+)\@(\S+)$/) {
			&line_error(&text('user_eextra1', $e));
			next USER;
			}
		local ($eu, $ed) = ($1, $2);
		local $edom = &get_domain_by("dom", $ed);
		if (!$edom || !$edom->{'mail'}) {
			&line_error(&text('user_eextra2', $ed));
			next USER;
			}
		if (!&can_edit_domain($edom)) {
			&line_error(&text('user_eextra3', $ed));
			next USER;
			}
		}

	# Validate forwarding addresses
	local @forward = split(/,/, $forwards);
	foreach $f (@forward) {
		if ($f !~ /\@/) {
			$f .= "\@$d->{'dom'}";
			}
		if ($f !~ /^[a-z0-9\.-\_\+]+\@[a-z0-9\.-\_\+]+$/) {
			&line_error(&text('umass_eto', $f));
			next USER;
			}
		}

	# Check if extras would exceed limit
	local ($mleft, $mreason, $mmax) = &count_feature("aliases");
	if ($mleft >= 0 &&
	    $mleft - @extra + (%old ? @{$old{'extraemail'}} : 0) < 0) {
		&line_error($text{'alias_ealiaslimit'});
		next USER;
		}

	# Validate databases
	local @dbs;
	foreach my $dbi (split(/,/, $dbs)) {
		local ($dbtype, $dbname) = split(/\s+/, $dbi);
		push(@dbs, { 'type' => $dbtype, 'name' => $dbname });
		}
	local @alldbs = &domain_databases($d);
	foreach my $db (@dbs) {
		($got) = grep { $_->{'type'} eq $db->{'type'} &&
				$_->{'name'} eq $db->{'name'} } @alldbs;
		if (!$got) {
			&line_error(&text('umass_edb', $db->{'name'}));
			next USER;
			}
		}

	# Build taken lists
	local (%taken, %utaken);
	&lock_user_db();
	&build_taken(\%taken, \%utaken);

	# Populate the user object
	local $user = &create_initial_user($d, 0, 0);
	if ($user->{'unix'} && !$user->{'webowner'}) {
		$user->{'uid'} = &allocate_uid(\%taken);
		}
	else {
		$user->{'uid'} = $d->{'uid'};
		}
	$user->{'gid'} = $d->{'gid'} || $d->{'ugid'};
	if ($user->{'person'}) {
		$user->{'real'} = $real;
		}
	if ($user->{'unix'}) {
		$user->{'shell'} = $ftp == 1 ? $config{'ftp_shell'} :
				   $ftp == 2 ? $config{'jail_shell'} :
					       $config{'shell'};
		}
	$user->{'passmode'} = 3;
	$user->{'plainpass'} = $pass;
	$user->{'pass'} = &encrypt_user_password($user, $pass);
	if (!$user->{'noextra'}) {
		$user->{'extraemail'} = \@extra;
		}
	if (@forward) {
		$user->{'to'} = \@forward;
		}
	if (!$user->{'fixedhome'}) {
		$user->{'home'} = "$d->{'home'}/$config{'homes_dir'}/$username";
		}
	if (($utaken{$username} || $config{'append'}) && !$user->{'noappend'}) {
		$user->{'user'} = &userdom_name($username, $d);
		}
	else {
		$user->{'user'} = $username;
		}
	if ($email && !$user->{'noprimary'}) {
		$user->{'email'} = "$username\@$d->{'dom'}"
		}
	else {
		$user->{'email'} = undef;
		}
	if ($user->{'unix'} && !$user->{'noquota'}) {
		$user->{'quota'} = $quota;
		$user->{'mquota'} = $mquota;
		}
	if ($user->{'mailquota'}) {
		$user->{'qquota'} = $qquota;
		}
	$user->{'dbs'} = \@dbs if (@dbs);

	if ($user->{'unix'}) {
		# Check for a Unix clash
		if ($utaken{$user->{'user'}} ||
		    &check_clash($username, $d->{'dom'})) {
			&line_error($text{'user_eclash'});
			next USER;
			}
		}

	# Check for clash within this domain
	local ($clash) = grep { $_->{'user'} eq $username &&
			  	$_->{'unix'} == $user->{'unix'} } @users;
	if ($clash) {
		&line_error($text{'user_eclash2'});
		next USER;
		}

	if (!$user->{'noextra'}) {
		# Check if any extras clash
		foreach my $e (@extra) {
			$e =~ /^(\S+)\@(\S+)$/;
			if (&check_clash($1, $2)) {
				&line_error(&text('user_eextra4', $e));
				next USER;
				}
			}
		}

	# Check if the name is too long
	if ($lerr = &too_long($user->{'user'})) {
		&line_error($lerr);
		next USER;
		}

	# Create the user and virtusers and alias
	&create_user($user, $d);

	if ($user->{'home'} && !$user->{'nocreatehome'}) {
		# Create his homedir
		&create_user_home($user, $d);
		}

	# Create an empty mail file, if needed
	if ($user->{'email'} && !$user->{'nomailfile'}) {
		&create_mail_file($user);
		}

	# Send an email upon creation
	@erv = &send_user_email($d, $user);

	&unlock_user_db();

	print "<font color=#00aa00>",
	      &text('umass_done', "<tt>$username</tt>"),"</font><br>\n";
	$count++;
	}

print "<p>\n";
print &text('umass_complete', $count, $ecount),"<br>\n";
&webmin_log("create", "users", $count);

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return'});

sub line_error
{
local ($msg) = @_;
print "<font color=#ff0000>";
if (!$username) {
	print &text('cmass_eline', $lnum, $msg);
	}
else {
	print &text('cmass_eline2', $lnum, $msg, "<tt>$username</tt>");
	}
print "</font><br>\n";
$ecount++;
}

