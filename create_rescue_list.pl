#!/usr/bin/perl

require "/home/qa-server/var/env_4_qa-server.pl";

use strict;
local $| = 1;

my $line;

my %protected_ip;

open( PROTECT, "< $ENV{'PXE_HOME'}/maps/mac_to_ip.protected" ) or die $!;

while( $line = <PROTECT> ){
	chomp($line);
	if( $line =~ /^(\d+\.\d+\.\d+\.\d+)/ ){
		$protected_ip{ $1 } = 1;
	};
};

close( PROTECT );

my %in_use;

open( INUSE, "< $ENV{'QA_IN_USE_LIST'}" ) or die $!;

while( $line = <INUSE> ){
	chomp($line);
	if( $line =~ /^(\d+\.\d+\.\d+\.\d+)\s+(.+)/ ){
		$in_use{ $1 } = $2;
	};
};

close( INUSE );


my @ip_lst;

print "\n\nReading the in_pxe.lst file to check the states of the machines\n\n";

open( INPXE, "< $ENV{'PXE_HOME'}/status/in_pxe.lst" ) or die $!;

while( $line = <INPXE> ){
	chomp($line);
	if( $line =~ /^(\d+\.\d+\.\d+\.\d+)\s+(.+)/ ){
		if( $2 eq "ERROR_IN_KS" ){
			print "$1 is stuck in $2\t";
			if( $protected_ip{ $1 } == 1 ){
				print "\tBut, it's protected\n";
			}elsif( $in_use{ $1 } ne "" ){
				print "\tit's taken by " . $in_use{$1} . "\n";
			}else{
				print "\n";
				push( @ip_lst , $1 );
			};
		};
	};
};

close( INPXE );

print "\n";

open( RESCUE, "> $ENV{'PXE_HOME'}/input/2b_rescued.lst" ) or die $!;

print RESCUE "PXE_TYPE\tQAIMAGE\n\n";

foreach my $this_ip ( @ip_lst ){
	print RESCUE "$this_ip\tcentos-qaimage\t6.3\t64\n";
};

close( RESCUE );

print "\nCreated the file 2b_rescued.lst in input directory\n";

print "\n#########################################################\n\n";
system("cat $ENV{'PXE_HOME'}/input/2b_rescued.lst");
print "\n#########################################################\n\n";

print "\n\n";


print "In order to rescue these machines, try :\n\n";
print "./trigger_kickstart.pl 2b_rescued.lst softreboot\n\n";
print "If it fails to rescue, try :\n\n";
print "./trigger_kickstart.pl 2b_rescued.lst hardreboot\n\n";


exit(0);

1;


