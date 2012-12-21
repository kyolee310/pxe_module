#!/usr/bin/perl
use strict;
use Cwd qw(chdir);

$ENV{'TEST_HOME'} = "/home/qa-server";
$ENV{'PXE_HOME'} = $ENV{'TEST_HOME'} . "/pxe_module";

my $test_name = "";

my @ip_lst = ();

my $needed_machine = 0;
my $machines_line;

if( @ARGV < 1 ){
	print "ERROR !! USAGE : ./add_ips_to_protected.pl <IPs>\n";
	exit(1);
};

my @ip_lst;

while(@ARGV > 0 ){
	push( @ip_lst, shift @ARGV );

};

foreach my $ip (@ip_lst ){
	print "Will add ".  $ip . "\n";
};

print "\n";

### Don't think it's necessary
#obtain_the_lock();

add_machines();

#release_the_lock();

print "\n\nNEW PROTECTED LIST\n";
print "cat $ENV{'PXE_HOME'}/maps/mac_to_ip.protected\n";

my $mynewlist = `cat $ENV{'PXE_HOME'}/maps/mac_to_ip.protected`;

print "\n";
print "=================================\n\n";
print "$mynewlist\n";
print "=================================\n\n";

exit(0);

1;



sub obtain_the_lock{
        if( ! (-e "$ENV{'PXE_HOME'}/status/.lock") ){
                system("$ENV{'PXE_HOME'}/status/.lock");
        };

        open( LOCK, "> $ENV{'PXE_HOME'}/status/.lock" );
        flock LOCK, 2;                  # lock the file
        sleep(1);
};

sub release_the_lock{
	
	close(LOCK);
};

sub add_machines{
	foreach my $t_ip ( @ip_lst ){
#		my $t_line = `cat $ENV{'PXE_HOME'}/maps/mac_to_ip.map | grep $t_ip | awk {'print \$3'}`;
		my $t_line = `cat $ENV{'PXE_HOME'}/maps/mac_to_ip.map | grep $t_ip`;
		chomp($t_line);

		if( $t_line =~ /^\S+\s+$t_ip\s+(\S+)/ ){
			$t_line = $1;

			if( $t_line =~ /\w+:\w+:\w+:\w+:\w+:\w+/ ){
				print "Adding the line\n";
				print $t_ip . "\t" . $t_line  . "\n";
				my $nu_line = $t_ip . "\t" . $t_line;
				
				system("echo \"$nu_line\"  >> $ENV{'PXE_HOME'}/maps/mac_to_ip.protected");
			};
		}else{
			print "Cannot find MAC for IP $t_ip !!\n";
		};
	}
	return 0;
};


