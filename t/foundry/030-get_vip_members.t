#!/usr/local/bin/perl 

use Test::More tests => 2;
use Test::Exception;

BEGIN {
	use FindBin;
	use lib "$FindBin::Bin/../../lib";
}

use Viper::LoadBalancer::Foundry;

my $lb = Viper::LoadBalancer::Foundry->new( 
    {
        host_name => 'lbf-5.pdq.yahoo.com',
        jump_host => 'tftp1.pdq.corp.yahoo.com',
        user_name => 'viper',
        password  => 'viper'
    }
);

# a previous test added this vip
my $vip_host = 'pc.pers.vip.mud.yahoo.com';

# a previous test added these vip members
my @vip_hosts;
lives_ok(
	sub {
		my $vip = $lb->get_vip_from_load_balancer($vip_host);
        @vip_hosts = map { $_->get_host_name() } @{ $vip->get_members() };
	},
	"get_vip_from_load_balancer"
);


is_deeply(
	\@vip_hosts,
	[
		qw(
		  md1.pers.mud.yahoo.com
		  md2.pers.mud.yahoo.com
		  md3.pers.mud.yahoo.com
		  )
	],
	"get_vip_members_from_load_balancer returned correct vip_members"
);
