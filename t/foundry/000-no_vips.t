#!/usr/local/bin/perl 

use Test::More tests => 3;
use Test::Exception;

BEGIN {
	use FindBin;
	use lib "$FindBin::Bin/../../lib";
}

use Viper::LoadBalancer::Foundry;

my $lb;
lives_ok(
	sub {
		$lb = Viper::LoadBalancer::Foundry->new(
			{
				host_name => 'lbf-5.pdq.yahoo.com',
				jump_host => 'tftp1.pdq.corp.yahoo.com',
				user_name => 'viper',
				password  => 'viper'
			}
		);
	},
	"create lb object"
);

my @vips;
lives_ok( sub { @vips = $lb->get_vips_from_load_balancer() }, "get_vips_from_load_balancer" );

is_deeply( \@vips, [], "no vips on lb" );
