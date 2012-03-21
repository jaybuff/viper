package Viper::Expect;

use strict;
use warnings;

use base 'Expect';

use Log::Log4perl qw(:easy);
use Viper;

# only send data to the log file whenever we see a new line
# this won't work in threaded apps.  sorry, but $self isn't
# a hash ref, so I don't know where else to stick the buffer
#
# I just realized that Expect.pm's log_file method can take a function.  not sure
# what that function is passed or what it is supposed to return, but that may
# be cleaner than this code and not require this child class
# however, not sure if that would allow me to timestamp the data
{
	my $buffer = '';

	sub print_log_file {    ## no critic (Subroutines::RequireArgUnpacking)
		my $self = shift;
		$buffer .= join( ' ', @_ );

		# since this is a wrapper class
		# see http://search.cpan.org/~mschilli/Log-Log4perl-1.16/lib/Log/Log4perl.pm#Using_Log::Log4perl_from_wrapper_classes
		$Log::Log4perl::caller_depth++;    ## no critic (ProhibitPackageVars)

		if ( $buffer =~ /\n$/ ) {
			foreach my $line ( split "\n", $buffer ) {
				INFO $line;
			}

			$buffer = '';
		}

		return;
	}
}

sub log_file {
	my $self      = shift;
	my $host_name = shift;

	set_log_file($host_name);
	return;
}

# this assumes that your log4perl config file looks something like this:
# log4perl.logger.Viper.Expect = DEBUG, A1
# log4perl.appender.A1= Log::Log4perl::Appender::File
# log4perl.appender.A1.filename = sub { use Viper::Expect; return Viper::Expect::get_log_file(); }
# log4perl.appender.A1.layout = Log::Log4perl::Layout::PatternLayout
# log4perl.appender.A1.layout.ConversionPattern = [%d] %m%n
# log4perl.additivity.A1 = 0
#
# log4perl.category         = DEBUG, Logfile
# log4perl.appender.Logfile = Log::Log4perl::Appender::File
# log4perl.appender.Logfile.filename = /home/y/logs/viper/viper_debug.log
# log4perl.appender.Logfile.layout = Log::Log4perl::Layout::PatternLayout
# log4perl.appender.Logfile.layout.ConversionPattern = [%d] %m%n
#
# notice the A1.filename part (third line)
{
	my $log_file;

	sub set_log_file {
		my $host_name = shift || '';

		my $config       = Viper->new()->get_config();
		my $log_base_dir = $config->get_log_base_dir();

		if ( !$log_base_dir || !-d $log_base_dir || !-w $log_base_dir ) {
			LOGDIE "log_base_dir in your config file is not set to a directory that is writable by user id $<";
		}

		$log_base_dir .= "/$host_name/";

		# if it doesn't exist create it
		if ( !-e $log_base_dir ) {
			mkdir $log_base_dir, oct(755) || LOGDIE "Failed to `mkdir 0755 $log_base_dir`: $!";
		}

		$log_file = $log_base_dir . "expect.log";

		# tell log4perl to call get_log_file again since it has changed
		# only do this if someone else initialized it
		if ( Log::Log4perl->initialized() ) {

			my $log_conf = $config->get_log_config_file();
			Log::Log4perl->init($log_conf);
		}

		return;

	}

	# the log4perl init file will call this function whenever it's init is called
	sub get_log_file {

		if ( !$log_file ) {
			set_log_file();
		}

		return $log_file;
	}
}

1;
__END__

=head1 NAME

Viper::Expect - extend Expect.pm to log expect input and output using Log4Perl

=head1 DESCRIPTION

Use Viper::Expect rather than Expect.pm and expect's log input and output will go to a log file

=head1 METHODS

=over 8

=item C<< Viper::Expect::set_log_file( $log_file ) >>

Globally sets where expect logging should go.  This is used by a Log4perl config setting like this:

    log4perl.logger.Viper.Expect = DEBUG, A1
    log4perl.appender.A1= Log::Log4perl::Appender::File
    log4perl.appender.A1.filename = sub { use Viper::Expect; return Viper::Expect::get_log_file(); }
    log4perl.appender.A1.layout = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.A1.layout.ConversionPattern = [%d] %m%n
    log4perl.additivity.A1 = 0

=item C<< my $log_file = Viper::Expect::get_log_file(); >>

See set_log_file().  This returns whatever that was set.  If set_log_file hasn't been called yet, it will 
default to log_base_dir config setting concatinated with "expect.log"

=item C<< Viper::Expect::log_file( $sub_dir ); >>

$log_base_dir is the config setting with the same name consider this example code:

    my $log_file = "$log_base_dir/$subdir/expect.log";

All logging will go into $log_file.

This is useful for giving each load balancer its own log file.

=item C<< Viper::Expect::print_log_file(); >>

Overridden method in Expect.pm that sends data to Log4perl rather than directly to file.

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
