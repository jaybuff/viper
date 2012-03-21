#!/usr/local/bin/perl 

use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;

BEGIN {
	use FindBin;
	use lib "$FindBin::Bin/../../lib";
}

use Viper::LoadBalancer::Foundry;

# for debuging 
#use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init($DEBUG);

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

my $port         = 80;
my $health_check = 'port http url "GET /status.html HTTP/1.0"';


# add these three hosts to the vip
foreach my $member_host (
	qw(
	md1.pers.mud.yahoo.com
	md2.pers.mud.yahoo.com
	md3.pers.mud.yahoo.com
	)
  )
{
	my $vip_member = Viper::LoadBalancer::VIP::Member->new(
		{
			port         => $port,
			health_check => $health_check,
			host_name    => $member_host,
		}
	);
	lives_ok(
		sub {
			$lb->add_member_to_vip( $vip_host, $vip_member );
		},
		"add_member_to_vip works for host $member_host"
	);
}

dies_ok(
	sub {
		my $vip_member = Viper::LoadBalancer::VIP::Member->new(
			{
				port         => $port,
				health_check => $health_check,
				host_name    => 'foo.doesnt.exist.yahoo.com',
			}
		);
		$lb->add_member_to_vip( $vip_host, $vip_member );
	},
	"add_member_to_vip dies when you add a host that doesn't exist in DNS"
);
