#!/usr/local/bin/perl

# Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
# Copyrights licensed under the New BSD License. 
# See the accompanying LICENSE file for terms.

use strict;
use warnings;

use Viper;
use Log::Log4perl qw(:easy);

my $viper = Viper->new();
my $log_conf = $viper->get_config()->get_log_config_file();
Log::Log4perl->init( $log_conf );

$viper->run();

DEBUG "done!";
