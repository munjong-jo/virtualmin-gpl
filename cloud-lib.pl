# Functions for generically handling cloud storage providers

# list_cloud_providers()
# Returns a list of hash refs with details of known providers
sub list_cloud_providers
{
return ( { 'name' => 's3',
	   'prefix' => [ 's3', 's3rrs' ],
	   'desc' => $text{'cloud_s3desc'} },
	 { 'name' => 'rs',
	   'prefix' => [ 'rs' ],
	   'desc' => $text{'cloud_rsdesc'} },
	 { 'name' => 'google',
	   'prefix' => [ 'google' ],
	   'desc' => $text{'cloud_googledesc'},
	   'longdesc' => $text{'cloud_googlelongdesc'} },
       );
}

# backup_uses_cloud(&backup, &provider)
# Checks if any dest of a backup uses this provider
sub backup_uses_cloud
{
my ($backup, $prov) = @_;
my @rv;
foreach my $d (&get_scheduled_backup_dests($backup)) {
	foreach my $p (@{$prov->{'prefix'}}) {
		if ($d =~ /^\Q$p\E:/) {
			push(@rv, $d);
			last;
			}
		}
	}
return wantarray ? @rv : $rv[0];
}

######## Functions for Amazon S3 ########

sub cloud_s3_get_state
{
if ($config{'s3_akey'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_s3account', $config{'s3_akey'}),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_s3_show_inputs
{
my $rv;

# Default login
$rv .= &ui_table_row($text{'cloud_s3_akey'},
	&ui_radio("s3_akey_def", $config{'s3_akey'} ? 0 : 1,
		  [ [ 1, $text{'cloud_noneset'} ],
		    [ 0, $text{'cloud_below'} ] ])."<br>\n".
	&ui_grid_table([ "<b>$text{'cloud_s3_access'}</b>",
		         &ui_textbox("s3_akey", $config{'s3_akey'}, 50),
		         "<b>$text{'cloud_s3_secret'}</b>",
                         &ui_textbox("s3_skey", $config{'s3_skey'}, 50) ], 2));

# S3 endpoint hostname, for non-amazon implementations
$rv .= &ui_table_row($text{'cloud_s3_endpoint'},
	&ui_opt_textbox("s3_endpoint", $config{'s3_endpoint'}, 40,
			$text{'cloud_s3_amazon'}));

# Upload chunk size
$rv .= &ui_table_row($text{'cloud_s3_chunk'},
	&ui_opt_textbox("s3_chunk", $config{'s3_chunk'}, 6,
			$text{'default'}." (5 MB)"));

return $rv;
}

sub cloud_s3_parse_inputs
{
my ($in) = @_;

# Parse default login
if ($in->{'s3_akey_def'}) {
	delete($config{'s3_akey'});
	delete($config{'s3_skey'});
	}
else {
	$in->{'s3_akey'} =~ /^\S+$/ || &error($text{'backup_eakey'});
	$in->{'s3_skey'} =~ /^\S+$/ || &error($text{'backup_eskey'});
	$config{'s3_akey'} = $in->{'s3_akey'};
	$config{'s3_skey'} = $in->{'s3_skey'};
	}

# Parse endpoint hostname
if ($in->{'s3_endpoint_def'}) {
	delete($config{'s3_endpoint'});
	}
else {
	&to_ipaddress($in->{'s3_endpoint'}) ||
		&error($text{'cloud_es3_endpoint'});
	$config{'s3_endpoint'} = $in->{'s3_endpoint'};
	}

# Parse chunk size
if ($in->{'s3_chunk_def'}) {
	delete($config{'s3_chunk'});
	}
else {
	$in->{'s3_chunk'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'cloud_es3_chunk'});
	$config{'s3_chunk'} = $in->{'s3_chunk'};
	}

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

######## Functions for Rackspace Cloud Files ########

sub cloud_rs_get_state
{
if ($config{'rs_user'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_rsuser', $config{'rs_user'}),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_rs_show_inputs
{
my $rv;

# Default login
$rv .= &ui_table_row($text{'cloud_rs_user'},
	&ui_radio("rs_user_def", $config{'rs_user'} ? 0 : 1,
		  [ [ 1, $text{'cloud_noneset'} ],
		    [ 0, $text{'cloud_below'} ] ])."<br>\n".
	&ui_grid_table([ "<b>$text{'cloud_rs_user'}</b>",
		         &ui_textbox("rs_user", $config{'rs_user'}, 50),
		         "<b>$text{'cloud_rs_key'}</b>",
                         &ui_textbox("rs_key", $config{'rs_key'}, 50) ], 2));

# Rackspace endpoint
my @eps = &list_rackspace_endpoints();
$rv .= &ui_table_row($text{'cloud_rs_endpoint'},
	&ui_select("rs_endpoint", $config{'rs_endpoint'}, \@eps, 1, 0, 1));

# Use internal address?
$rv .= &ui_table_row($text{'cloud_rs_snet'},
	&ui_yesno_radio("rs_snet", $config{'rs_snet'}));

# Upload chunk size
$rv .= &ui_table_row($text{'cloud_rs_chunk'},
	&ui_opt_textbox("rs_chunk", $config{'rs_chunk'}, 6,
			$text{'default'}." (200 MB)"));

return $rv;
}

sub cloud_rs_parse_inputs
{
my ($in) = @_;

# Parse default login
if ($in->{'rs_user_def'}) {
	delete($config{'rs_user'});
	delete($config{'rs_key'});
	}
else {
	$in->{'rs_user'} =~ /^\S+$/ || &error($text{'backup_ersuser'});
	$in->{'rs_key'} =~ /^\S+$/ || &error($text{'backup_erskey'});
	$config{'rs_user'} = $in->{'rs_user'};
	$config{'rs_key'} = $in->{'rs_key'};
	}

# Parse endpoint
$config{'rs_endpoint'} = $in{'rs_endpoint'};

# Parse internal network flag
$config{'rs_snet'} = $in{'rs_snet'};

# Parse chunk size
if ($in->{'rs_chunk_def'}) {
	delete($config{'rs_chunk'});
	}
else {
	$in->{'rs_chunk'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'cloud_es3_chunk'});
	$config{'rs_chunk'} = $in->{'rs_chunk'};
	}

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

sub list_rackspace_endpoints
{
return ( [ 'https://identity.api.rackspacecloud.com/v1.0', 'US default' ],
	 [ 'https://lon.auth.api.rackspacecloud.com/v1.0', 'UK default' ],
	 [ 'https://identity.api.rackspacecloud.com/v1.0;DFW', 'US - Dallas' ],
	 [ 'https://identity.api.rackspacecloud.com/v1.0;ORD', 'US - Chicago' ] );
}


######## Functions for Google Cloud Storage ########

sub cloud_google_get_state
{
if ($config{'google_account'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_gaccount', $config{'google_account'},
				 $config{'google_project'}),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_google_show_inputs
{
my $rv;

# Google account
$rv .= &ui_table_row($text{'cloud_google_account'},
	&ui_textbox("google_account", $config{'google_account'}, 40));

# Google OAuth2 client ID
$rv .= &ui_table_row($text{'cloud_google_clientid'},
	&ui_textbox("google_clientid", $config{'google_clientid'}, 40));

# Google client secret
$rv .= &ui_table_row($text{'cloud_google_secret'},
	&ui_textbox("google_secret", $config{'google_secret'}, 40));

# GCE project name
$rv .= &ui_table_row($text{'cloud_google_project'},
	&ui_textbox("google_project", $config{'google_project'}, 40));

return $rv;
}

sub cloud_google_parse_inputs
{
my ($in) = @_;

# Parse google account
$in->{'google_account'} =~ /^\S+\@\S+$/ ||
	&error($text{'cloud_egoogle_account'});
$config{'google_account'} = $in->{'google_account'};

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

######## Functions for Dropbox ########

sub cloud_dropbox_get_state
{
}

1;