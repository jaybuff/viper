#!/usr/local/bin/perl 

use Test::More tests => 5;

BEGIN {
	use FindBin;
	use lib "$FindBin::Bin/../lib";
}

foreach my $class (
	qw(
    Viper
    Viper::Util
    Viper::Config
	Viper::LoadBalancer
	Viper::LoadBalancer::Foundry
	)
  )
{
	use_ok( $class, "use_ok $class" );
}
