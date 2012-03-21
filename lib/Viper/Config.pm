package Viper::Config;

use strict;
use warnings;

use base 'Config::YAML';


sub new {
	return Config::YAML->new(
		config => $ENV{VIPER_CONFIG_FILE} || '/etc/viper.conf',
		output => "~/.viperrc",
	);
}

1;
__END__

=head1 NAME

Viper::Config - Access viper config options

=head1 DESCRIPTION

Put some config options in a file and be able to access them.

The file containing the config options is to be set by the environment variable VIPER_CONFIG_FILE.  If that isn't set it defaults to /etc/viper.conf

=head1 METHODS

=over 8

=item C<< my $config = Viper::Config->new(); >>

Create a Viper config option.  Uses Config::YAML to read the yaml file in the environment variable VIPER_CONFIG_FILE.  
If that isn't set it defaults to /etc/viper.conf

=item C<< $config->get_config_option(); >>

Any setting you put in the config file can be accessed with a standard getter.  So if you have this in your config file:

    debug: 1

then you can access the value of debug with $config->get_debug();

See Config::YAML for more info.

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
