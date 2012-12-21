#!/usr/bin/perl

use strict;

local $| = 1;

$ENV{'TEST_HOME'} = "/home/qa-group";
$ENV{'PXE_HOME'} = $ENV{'TEST_HOME'} . "/pxe_module";
$ENV{'MAILBOX'} = "/home/mailman/mailbox";

$ENV{'METALEUCA_DIR'} = "/home/qa-group/metaleuca";

require "$ENV{'PXE_HOME'}/lib/timed_run.pl";

chdir($ENV{'PXE_HOME'});

if( @ARGV < 4 ){
	print "[Error]\tNeeds 4 arguments\n";
	print "USAGE: ./kickstart_a_machine_via_cobbler.pl <ip> <distro_image> <version> <arch>\n";
	exit(1);
};

print "IP\t$ARGV[0]\n";
print "DISTRO\t$ARGV[1]\n";
print "VERSION\t$ARGV[2]\n";
print "ARCH\t$ARGV[3]\n";

my $ip = $ARGV[0];
my $distro = lc($ARGV[1]);
my $version = lc($ARGV[2]);
my $arch = $ARGV[3];

my $is_hardreboot = 0;
my $is_softreboot = 0;

if( $ARGV[4] eq "hardreboot" ){
	$is_hardreboot = 1;
	print "\nNOTE\tHARD-REBOOT MODE\n\n";
}elsif( $ARGV[4] eq "softreboot" ){
	$is_softreboot = 1;
        print "\nNOTE\tSOFT-REBOOT MODE\n\n";
};

my $this_timeout = 25;			### from 20 to 25 for SCALE test	ADDED 012712

if( $distro =~ /qaimage/ ){		### if the image is for QA, half the timeout
	$this_timeout = 15;		### TO SEE IF THIS WILL REDUCE THE PXE FAILURE RATE	062811 
};


my $image;
my $line;

open( PROTECT, "< $ENV{'PXE_HOME'}/maps/mac_to_ip.protected" ) or die $!;
while ( $line = <PROTECT> ){
	chomp($line);
	if( $line =~ /^(\d+\.\d+\.\d+\.\d+)\s+/ ){
		if( $ip eq $1 ){
			print "[ERROR]\tIP $ip is protected from PXEBOOT!!\n";
			exit(1);
		};
	};
};
close(PROTECT);


open( IMAGE, "< $ENV{'PXE_HOME'}/maps/distro_image_map_for_cobbler.list" ) or die $!;
while ( $line = <IMAGE> ){
        chomp($line);
        if( $line =~ /^(.+)\t(.+)\t(\d+)\t(.+)/ ){
                if( $1 eq "$distro" && $2 eq "$version" && $3 eq "$arch"  ){
                        print "[ DISTRO $distro, VERSION $version, ARCH $arch ] maps to IMAGE $4\n";
			$image = $4;
                };
        };
};
close(IMAGE);


if( $image eq "" ){
	if( $is_hardreboot == 0 && $is_softreboot == 0 ){
		print "ERROR : Couldn't map [ DISTRO $distro, VERSION $version, ARCH $arch ] to an IMAGE!!\n";
		exit(1);
	}else{						### in HARD-REBOOT or SOFT-REBOOT MODE, use default image
		$image = "qa-centos6u3-x86_64-striped-drives";
		print "ERROR : Couldn't map [ DISTRO $distro, VERSION $version, ARCH $arch ] to an IMAGE!!\n";
		print "IN HARD-REBOOT MODE, DEFAULT IMAGE $image will be used\n";
	};
};


### WRITE 2b-pxebooted- FILE in ./which_image

if( $distro ne "buildimage" ){						### EXCEPTION for buildimage CASE

	if( -e "$ENV{'PXE_HOME'}/which_image/2b-pxebooted-$ip" ){
		system("rm -f $ENV{'PXE_HOME'}/which_image/2b-pxebooted-$ip");
	};

	system("touch $ENV{'PXE_HOME'}/which_image/2b-pxebooted-$ip");

	open( NEWFILE, "> $ENV{'PXE_HOME'}/which_image/2b-pxebooted-$ip" ) or die;
	print NEWFILE "$ip\t$image\n";
	close( NEWFILE );

	print "\nCreated the file 2b-pxebooted-$ip in $ENV{'PXE_HOME'}/which_image\n\n"; 

};

### REMOVE MAILS

if( -e "$ENV{'PXE_HOME'}/mailbox/completed:$ip" ){
	print "Removing the file completed:$ip from $ENV{'PXE_HOME'}/mailbox\n";
	system("rm -f $ENV{'PXE_HOME'}/mailbox/completed:$ip");
};
if( -e "$ENV{'PXE_HOME'}/mailbox/distro-ready:$ip" ){
	print "Removing the file distro-ready:$ip from $ENV{'PXE_HOME'}/mailbox\n";
	system("rm -f $ENV{'PXE_HOME'}/mailbox/distro-ready:$ip");
};
if( -e "$ENV{'MAILBOX'}/$ip" ){
        print "Removing the file $ip from $ENV{'MAILBOX'}/\n";
        system("rm -f $ENV{'MAILBOX'}/$ip");
};

### REMOVE known_hosts RECORD
print "ssh-keygen -f \"/home/qa-group/.ssh/known_hosts\" -R $ip\n";
system("ssh-keygen -f \"/home/qa-group/.ssh/known_hosts\" -R $ip");
print "\n";

### ENABLING KICKSTART

#system("$ENV{'PXE_HOME'}/modify_pxeboot_option.pl $ip $image");


### REBOOT THE MACHINE

print print_time() . "Sending Reboot Signal to IP $ip\n";

my $conn_ok = 0;

### IN HARD-REBOOT MODE, Always try to reboot the machine via LO100 <- not apply for new datacenter
if ( $is_hardreboot == 0 ){
	
	print "\n";
	print "Performing Metaleuca Calls on $ip\n";
	print "\n";

	###	metaleuca-run-instances Cannot be used due to the conflicting machine reservation
	###	Machines are already reserved at the QA controller level
#	my $rc = timed_run("cd $ENV{'METALEUCA_DIR'}; ./metaleuca-run-instances -i $ip -p $image -u qa-server", 120);

	###	Instead, break down the metaleuca calls for provisioning
	timed_run("cd $ENV{'METALEUCA_DIR'}; ./metaleuca-set-profile -i $ip -p $image", 60);
	
	my $metaleuca_run = get_recent_outstr();
	chomp($metaleuca_run);
	print "\n";
	print "$metaleuca_run\n";
	print "\n";
	
	timed_run("cd $ENV{'METALEUCA_DIR'}; ./metaleuca-enable-netboot -i $ip", 60);
	
	$metaleuca_run = get_recent_outstr();
	chomp($metaleuca_run);
	print "\n";
	print "$metaleuca_run\n";
	print "\n";

	my $rc = timed_run("cd $ENV{'METALEUCA_DIR'}; ./metaleuca-reboot-system -i $ip", 120);
	
	$metaleuca_run = get_recent_outstr();
	chomp($metaleuca_run);
	print "\n";
	print "$metaleuca_run\n";
	print "\n";			

	if( $rc == 0 ){
		print "\n";
		print print_time() . "Reboot Signal has been sent to IP $ip\n";
		print "\n";

		$conn_ok = 1;
	};
};

###
###	CONCERN: Since hard-reboot is disabled, how do we ensure that the machine was actually rebooted?	
###
if( $conn_ok == 0){

	###	NEW DATACETNER CASE
	print "ERROR: Couldn't Initiate Reboot to the Machine $ip\n";
	exit(1);
};

chdir("$ENV{'PXE_HOME'}");

### REMOVE known_hosts RECORD
print "ssh-keygen -f \"/home/qa-group/.ssh/known_hosts\" -R $ip\n";
system("ssh-keygen -f \"/home/qa-group/.ssh/known_hosts\" -R $ip");
print "\n";

### CHECKING THE MAILBOX AFTER PXEBOOR

print "Machine $ip is engaged in KICKSTART. It will take about 7 to 20 minutes(ticks)\n";

my $done = 0;
my $timer = 0;

while($done == 0){

	if( -e "$ENV{'MAILBOX'}/$ip" ){
		print "\n";
		$done = 1;
	}else{
		print "$ip says \"tick\t$timer...\"\n";
		sleep(60);
		$timer = $timer + 1;

		if( $timer > 7 ){
			### REMOVE known_hosts RECORD
			system("ssh-keygen -f \"/home/qa-group/.ssh/known_hosts\" -R $ip > /dev/null 2> /dev/null");

			print "$ip says \"Knock Knock...\"\n";

			if( $distro =~ /vmware/ ){
				my $check_vmware = `ssh -o BatchMode=yes -o ServerAliveInterval=3 -o ServerAliveCountMax=10 -o StrictHostKeyChecking=no root\@$ip \"uname -a\"`;
				if( $check_vmware =~ /^VMkernel/ || $check_vmware =~ /ESX/ ){
					system("touch $ENV{'MAILBOX'}/$ip");
					system("sudo chown mailman:mailman $ENV{'MAILBOX'}/$ip");
					system("sudo chmod 664 $ENV{'MAILBOX'}/$ip");
				};
			}else{
				my $check_bootup = `ssh -o BatchMode=yes -o ServerAliveInterval=3 -o ServerAliveCountMax=10 -o StrictHostKeyChecking=no root\@$ip \"uname -r\"`;
				if( $check_bootup =~ /^\d+/ ){
					system("touch $ENV{'MAILBOX'}/$ip");
					system("sudo chown mailman:mailman $ENV{'MAILBOX'}/$ip");
					system("sudo chmod 664 $ENV{'MAILBOX'}/$ip");
				};

			};
		};

		if( $timer > $this_timeout ){
			print "\n TIMEOUT !!! [" . $this_timeout . " mins]\n";
			# disabling the machine from pxeboot since we don't want this machine to be stuck in pxeboot loop
			timed_run("cd $ENV{'METALEUCA_DIR'}; ./metaleuca-disable-netboot -i $ip", 60);
			$done = 2;
		};

	};
};

if( $done == 1){
	print "\n" . print_time() . "IP $ip is successfully kickstarted with DISTRO $distro, VERSION $version, and ARCH $arch\n";
	exit(0);
}else{
	print "\n" . print_time() . "IP $ip is FAILED to be kickstarted with DISTRO $distro, VERSION $version, and ARCH $arch\n";
	exit(1);
};


exit(0);

1;

sub print_time{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst)=localtime(time);
        my $this_time = sprintf "[%4d-%02d-%02d %02d:%02d:%02d]\t", $year+1900,$mon+1,$mday,$hour,$min,$sec;
	return $this_time;
};

