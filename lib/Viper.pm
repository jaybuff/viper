package Viper;

use strict;
use warnings;

use Viper::Config;
use Log::Log4perl qw(:easy);
use Module::Load ();
use version; our $VERSION = qv("0.0.5");


sub new {
	my $proto = shift;
	my $class = ref $proto || $proto;

	return bless {}, $class;
}

sub get_data_source {
	my $self = shift;
	if ( $self->{data_source_object} ) {
		return $self->{data_source_object};
	}

	my $data_source_module = $self->get_config()->get_data_source_module();
	if ( !$data_source_module ) {
		LOGDIE "invalid config file, you must define get_data_source_module setting";
	}

    DEBUG "loading $data_source_module";
    Module::Load::load( $data_source_module );

	$self->{data_source_object} = $data_source_module->new();

	# make sure that the data source class has all the required methods
	foreach my $method (qw( get_vips get_vip_members )) {
		if ( !$self->{data_source_object}->can($method) ) {
			LOGDIE "$data_source_module must implement a $method method\n";
		}
	}

	return $self->{data_source_object};
}

sub run {
	my $self = shift;

	my $data_source = $self->get_data_source();
    DEBUG "Running.. iterating through all load balancers";
	foreach my $lb ( $data_source->get_load_balancers() ) {
		$lb->sync_vips();
	}
    DEBUG "Done!";

	return;
}

sub get_config {
	my $self = shift;
	if ( $self->{viper_config} ) {
		return $self->{viper_config};
	}

	return $self->{viper_config} = Viper::Config->new();
}

1;

__END__

=head1 NAME

Viper - manage a collection of load balancers and VIPs

=head1 DESCRIPTION

Viper is a system that will read a list of load balancers, VIPs on those load balancers and members i
n those VIPs from a data source and configure those load balancers to use them. Viper to talk to any
type of load balancer that a plugin has been written for. Writing plugins is fairly straight forward;
 its just a handful of expect commands.

=head1 SYNOPSIS

    my $viper = Viper->new();

    # get the Viper::Config object
    my $config = $viper->get_config();

    # get the Viper::Plugin::DataSource object
    my $data_source = $viper->get_data_source();

=head1 METHODS

=over 8

=item C<< my $viper = Viper->new() >>

=item C<< $viper->run() >>

Get all the load balancers from the datasource, and call sync_vips() on all of them.

=item C<< my $config = $viper->get_config() >>

Return an initialized Viper::Config object

=item C<< my $data_source = $viper->get_data_source() >>

returns a Viper::Plugin::DataSource object

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut

