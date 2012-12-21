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
	print "ERROR !! USAGE : ./reset_ks_status_by_ips.pl <IPs>\n";
	exit(1);
};

my @ip_lst;

while(@ARGV > 0 ){
	push( @ip_lst, shift @ARGV );

};

foreach my $ip (@ip_lst ){
	print "Will reset ".  $ip . "\n";
};

print "\n";

### Don't think it's necessary since it only adjusts the status to UP, which is good.
#obtain_the_lock();

release_machines();

#release_the_lock();


print "\n\nNEW KICKSTART STATUS\n";
print "cat $ENV{'PXE_HOME'}/status/in_pxe.lst\n";

my $mynewlist = `cat $ENV{'PXE_HOME'}/status/in_pxe.lst`;

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

sub release_machines{

	system( "mv $ENV{'PXE_HOME'}/status/in_pxe.lst $ENV{'PXE_HOME'}/status/in_pxe.lst.backup" );

	open(STAT, "< $ENV{'PXE_HOME'}/status/in_pxe.lst.backup") or die $!;
        open( NEW, "> $ENV{'PXE_HOME'}/status/in_pxe.lst") or die $!;
	my $line;
        while( $line = <STAT> ){
                chomp($line);
		my $this_ip = "";
		if( $line =~ /^([\d\.]+)\s+/ ){
			$this_ip = $1;
			my $foundit = 0;
			foreach my $target_ip ( @ip_lst ){
				if( $line =~ /^$target_ip\s+/ ){
					$foundit = 1;
				};
			};

                	if( $foundit == 1 ){			                        # RESET
				print "$this_ip is reset to UP\n";
				print NEW "$this_ip\tUP\n";
                	}else{
                	        print NEW $line . "\n";
                	};
		}else{
			print NEW $line . "\n";
		};
        };
        close(NEW);
        close(STAT);

        return 0;
};


