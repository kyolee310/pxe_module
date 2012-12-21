#!/usr/bin/perl

use strict;

local $| = 1;

$ENV{'PXE_HOME'} = "/home/qa-group/pxe_module";
$ENV{'MAILBOX'} = "/home/mailman/mailbox";

if( !( -e "$ENV{'PXE_HOME'}/status/pxe_error.log") ){
	system("touch $ENV{'PXE_HOME'}/status/pxe_error.log");
};

my $admin_email = "kyo.lee\@eucalyptus.com";
my $inputfile = "2b_rebooted.lst";			## default input file

if( @ARGV > 0 ){
	$inputfile = shift @ARGV;
};

my $is_hardreboot = 0;
my $is_softreboot = 0;

if( @ARGV > 0 ){
	my $temp_argv = shift @ARGV;
	if( $temp_argv eq "hardreboot" ){
		print "\nNOTE\tHARD-REBOOT MODE\n\n";
		$is_hardreboot = 1;
	}elsif( $temp_argv eq "softreboot" ){
		print "\nNOTE\tSOFT-REBOOT MODE\n\n";
                $is_softreboot = 1;
	};
};

my $line;

### Get the list of IPs that are protected from PXEBOOT

my %protected;

open( PROTECT, "< $ENV{'PXE_HOME'}/maps/mac_to_ip.protected" ) or die;

while ( $line = <PROTECT> ){
        chomp($line);
        if( $line =~ /(\d+\.\d+\.\d+\.\d+)/ ){
		$protected{ $1 } = 1;
        };
};

close(PROTECT);

my %in_use;

open( IN_USE, "< $ENV{'PXE_HOME'}/status/in_pxe.lst" ) or die;

while ( $line = <IN_USE> ){
        chomp($line);
        if( $line =~ /^(\d+\.\d+\.\d+\.\d+)\s+(.+)/ ){
		if( $2 ne "UP" && $is_hardreboot == 0 && $is_softreboot == 0 ){		### in HARD-REBOOT MODE, IGNORE the PXE condition
                	$in_use{ $1 } = 1;
		};
        };
};

close( IN_USE );

### Read the input file 

my @ip_lst;
my @distro_lst;
my @version_lst;
my @arch_lst;
my $arch = 64;
my $pxe_type = "SNAPSHOT";
my $this_email = "";

my $ip_count = 0;
my $windows_first_index = -1;
my $windows_ips = "";

open( LIST, "$ENV{'PXE_HOME'}/input/$inputfile" ) or die $!;

while( $line = <LIST> ){
	chomp($line);
	if( $line =~ /^([\d\.]+)\s+(.+)\s+(.+)\s+(\d+)/ ){

		my $this_ip = $1;
		my $this_distro = $2;
		my $this_ver = $3;
		my $this_arch = $4;			

		if( $protected{ $this_ip } ){
			print "ERROR : IP $this_ip is protected from PXEBOOT !!!\n";
			print "Aborting ...\n";
			exit(1);
		}elsif( $in_use{ $this_ip } ){
			print "ERROR : IP $this_ip 's PXEBOOT state is not UP !!!\n";
			print "Please check out the file in_pxe.lst in ./status directory\n";
                        print "Aborting ...\n";
                        exit(1);
		}else{

			print "[ IP $this_ip, DISTRO $this_distro, VERSION $this_ver, ARCH $this_arch ]\n";

			push( @ip_lst, $this_ip );
			push( @distro_lst, $this_distro );
			push( @version_lst, $this_ver );
                        push( @arch_lst, $this_arch );
			if( $this_distro eq "windows" || $this_distro eq "WINDOWS" ){
				if( $windows_first_index == -1 ){
					$windows_first_index = $ip_count;
				};
				$windows_ips .= $this_ip . " ";
			};
			$ip_count++;
		};
	}elsif( $line =~ /^PXE_TYPE\s+(\w+)/  ){
                $pxe_type = $1;
	}elsif( $line =~ /^EMAIL\s+(.+)/ ){
		$this_email = $1;
	};
};

close( LIST );

chop($windows_ips);

### The machines on the input list are safe to PXEBOOT

if( !( -e "$ENV{'PXE_HOME'}/status/.lock") ){
	system("touch $ENV{'PXE_HOME'}/status/.lock");
};

open( LOCK, "> $ENV{'PXE_HOME'}/status/.lock");			### Obtain the LOCK
flock LOCK, 2;

my %plist;							### hash to keep track of machine state

mark_machines_in_use();

up_pxe_counter_file();

close( LOCK );							### Release the LOCK

my $ip_string = "Kickstart Request\n\n";

print "Cleaning up the PXEBOOT Mailbox\n";

for( my $i = 0; $i < @ip_lst; $i++){
	my $mailname_c = "$ENV{'PXE_HOME'}/mailbox/completed:" . $ip_lst[$i];
	my $mailname_d = "$ENV{'PXE_HOME'}/mailbox/distro-ready:" . $ip_lst[$i];
	if( -e "$mailname_c" ){
		print "Removing $mailname_c\n";
		system("rm -f $mailname_c");
	};
	if( -e "$mailname_d" ){
                print "Removing $mailname_d\n";
		system("rm -f $mailname_d");
        };
	$ip_string .= $ip_lst[$i] . "\t" . $distro_lst[$i] . "\t" . $version_lst[$i] . "\t" . $arch_lst[$i] . "\n";
};

print "\n";
if( $this_email ne "" ){
	print print_time() . "Sending Email to $this_email\n\n";
	sendMail($this_email, $admin_email, "[KICKSTART] Kickstart Started on " . $ip_lst[0] . " ..." , print_time() . " " . $ip_string);
	if( $this_email ne $admin_email ){
		sendMail($admin_email, $admin_email, "[KICKSTART] Kickstart Started on " . $ip_lst[0] . " ..." , print_time() . " " . $ip_string . "\n" . $this_email);
	};
};

print print_time() . "Initiating KICKSTART\n\n";

my @pids;

for( my $i = 0; $i < @ip_lst; $i++){
	
	$pids[$i] = fork();
	
	if(not defined $pids[$i]) {
		print "Failed in fork(): ID $i\nAborting...";
		exit(1);
	}elsif($pids[$i] == 0) {
		print "CHILD $i :: \n";
		print "Triggering KICKSTART on\n";

		### NEW DATACENTER KICKSTART VIA COBBLER	090812

		print "IP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
		print "\n";

		if( $is_hardreboot == 1 ){
			system("perl $ENV{'PXE_HOME'}/kickstart_a_machine_via_cobbler.pl $ip_lst[$i] $distro_lst[$i] $version_lst[$i] $arch_lst[$i] hardreboot");
		}elsif( $is_softreboot == 1 ){
			system("perl $ENV{'PXE_HOME'}/kickstart_a_machine_via_cobbler.pl $ip_lst[$i] $distro_lst[$i] $version_lst[$i] $arch_lst[$i] softreboot");
		}else{
			system("perl $ENV{'PXE_HOME'}/kickstart_a_machine_via_cobbler.pl $ip_lst[$i] $distro_lst[$i] $version_lst[$i] $arch_lst[$i]");
		};

		print "CHILD $i :: Completed KICKSTART on\n";
		print "IP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
		print "\n";

		exit(0);
	};
};

for( my $i = 0 ; $i < @ip_lst; $i++){
	print "PARENT :: Waiting on CHILD $i :: PID $pids[$i] IP $ip_lst[$i]\n";
	waitpid($pids[$i],0);
};

print "\n";
print print_time() . "All the fork() Processes Returned\n\n";
print "Checking the Mailbox\n";
print "KICKSTART RESULT\n";

my $result = 0;
my $dd_ok_count = 0;

for( my $i = 0; $i < @ip_lst; $i++){

	my $mailname_c = "$ENV{'MAILBOX'}/" . $ip_lst[$i];

        if( -e "$mailname_c" ){
		print "SUCCEEDED\tIP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
		$plist{ $ip_lst[$i] } = "SUCCESS_IN_KS";
		$dd_ok_count++;
        }else{
		print "FAILED!!!\tIP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
		$plist{ $ip_lst[$i] } = "ERROR_IN_KS";
		$result = 1;

		my $error_message = print_time(). "\nFAILED PXE\tIP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";

		my $prev_distro_info = "";
		my $fip = $ip_lst[$i];

		open(TEMPTEMP,  "< $ENV{'PXE_HOME'}/status/in_pxe.distro" );

		my $li;
		while( $li = <TEMPTEMP> ){
			chomp($li);
			if( $li =~ /^$fip\s/ ){
				$prev_distro_info = "$li";
			};
		};
		close(TEMPTEMP);

		$error_message .= "PREVIOUS INFO\t$prev_distro_info\nEND\n\n";

		open(PXEERROR, ">> $ENV{'PXE_HOME'}/status/pxe_error.log");
		print PXEERROR "$error_message";
		close(PXEERROR);

	};

};


my %rebooted;

for( my $i = 0; $i < @ip_lst; $i++){
	$rebooted{ $ip_lst[$i] } = 0;
};

my $done = 0;
my $reboot_timer = 0;

my $result_string = "Kickstart Result\n\n";

while( $done == 0 ){
	for( my $i = 0; $i < @ip_lst; $i++){
		if( $plist{ $ip_lst[$i] } eq "SUCCESS_IN_KS" ){
			### NORMAL PXEBOOT
			my $confirm = `ping -c 3 $ip_lst[$i] | grep received`;
			print $confirm;
			if( $confirm =~ /(\d)\sreceived/ ){
				if( $1 == 3 ){
					$rebooted{ $ip_lst[$i] } = 1;
					$plist{ $ip_lst[$i] } = "UP";
				};
			};
		};
	};

	print "\nREBOOT RESULT\n";
	my $up_count = 0;
	for( my $i = 0; $i < @ip_lst; $i++){
		if( $rebooted{ $ip_lst[$i] } == 1 ){
			print "UP AND RUNNING\tIP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
			$result_string .= "UP AND RUNNING\t" . $ip_lst[$i] . "\t" . $distro_lst[$i] . "\t" . $version_lst[$i] . "\t" . $arch_lst[$i] . "\n";
			$up_count++;
		}else{
			if( $plist{ $ip_lst[$i] } eq "SUCCESS_IN_KS" ){
				print "DOWN\tIP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
				$result_string .= "DOWN\t" . $ip_lst[$i] . "\t" . $distro_lst[$i] . "\t" . $version_lst[$i] . "\t" . $arch_lst[$i] . "\n";
			}else{
				print $plist{ $ip_lst[$i] } .  "\tIP " . $ip_lst[$i] . "\tDISTRO " . $distro_lst[$i] . "\tVERSION " . $version_lst[$i] . "\tARCH " . $arch_lst[$i] . "\n";
				$result_string .= $plist{ $ip_lst[$i] } .  "\t" . $ip_lst[$i] . "\t" . $distro_lst[$i] . "\t" . $version_lst[$i] . "\t" . $arch_lst[$i] . "\n";
			};
		};
        };

	if( $up_count == $dd_ok_count ){
		$done = 1;
	}else{
		sleep(60);
		$reboot_timer++;

		if( $reboot_timer > 5 ){
			print "TIMEOUT !!! [5 mins]\n";
			$done = 2;
		}else{
			$result_string = "";
		};

	};
};

open( LOCK, "> $ENV{'PXE_HOME'}/status/.lock");                 ### Obtain the LOCK
flock LOCK, 2;

mark_machines_result();
down_pxe_counter_file();
record_distro();

close( LOCK );							### Release the LOCK

								### SEND EMAIL 

if( $done == 1 && $result == 0 ){
	if( $this_email ne "" ){
	        print print_time() . "Sending Email to $this_email\n\n";
	        sendMail($this_email, $admin_email, "[KICKSTART] Kickstart Completed on " . $ip_lst[0] . " ..." , print_time() . " " . $result_string);
		if( $this_email ne $admin_email ){
			sendMail($admin_email, $admin_email, "[KICKSTART] Kickstart Completed on " . $ip_lst[0] . " ..." , print_time() . " " . $result_string);
		};
		record_kickstart_event($this_email, print_time(), $result_string);
	};

	print "\n" . print_time() ."KICKSTART COMPLETED\n";
	exit(0);
}else{
	if( $this_email ne "" ){
	        print print_time() . "Sending Email to $this_email\n\n";
	        sendMail($this_email, $admin_email, "[KICKSTART] Kickstart FAILED on " . $ip_lst[0] . " ..." , print_time() . "\t" . $result_string);
		if( $this_email ne $admin_email ){
			sendMail($admin_email, $admin_email, "[KICKSTART] Kickstart FAILED on " . $ip_lst[0] . " ..." , print_time() . " " . $result_string);
		};
	};

	print "\n" . print_time() . "SOME MACHINES HAVE FAILED TO KICKSTART\n";
	exit(1);
};



exit(0);

1;


sub print_time{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst)=localtime(time);
        my $this_time = sprintf "[%4d-%02d-%02d %02d:%02d:%02d]\t", $year+1900,$mon+1,$mday,$hour,$min,$sec;
	return $this_time;
};



sub mark_machines_in_use{

	open( PLIST, "< $ENV{'PXE_HOME'}/status/in_pxe.lst" ) or die $!;

	while($line = <PLIST>){
	        chomp($line);
	        if( $line =~ /^([\d\.]+)\s+(.+)/ ){
	                $plist{ $1 } = $2;
	        };
	};

	close(PLIST);

	foreach my $k ( @ip_lst ){
	        $plist{ $k } = "IN_USE";
	};

	system("mv -f $ENV{'PXE_HOME'}/status/in_pxe.lst $ENV{'PXE_HOME'}/status/in_pxe.lst.backup");

	open( NEWPLIST, "> $ENV{'PXE_HOME'}/status/in_pxe.lst" ) or die $!;

	foreach my $key (sort (keys %plist)){
	        print NEWPLIST $key . "\t" . $plist{ $key } ."\n";
	};

	close( NEWPLIST );

	system("chmod 664 $ENV{'PXE_HOME'}/status/in_pxe.lst");

	return 0;
};

sub mark_machines_result{

        open( PLIST, "< $ENV{'PXE_HOME'}/status/in_pxe.lst" ) or die $!;

	my %newplist;

        while($line = <PLIST>){
                chomp($line);
                if( $line =~ /^([\d\.]+)\s+(.+)/ ){
                        $newplist{ $1 } = $2;
                };
        };

        close(PLIST);

        foreach my $k ( @ip_lst ){
                $newplist{ $k } = $plist{ $k };
        };

        system("mv -f $ENV{'PXE_HOME'}/status/in_pxe.lst $ENV{'PXE_HOME'}/status/in_pxe.lst.backup");

        open( NEWPLIST, "> $ENV{'PXE_HOME'}/status/in_pxe.lst" ) or die $!;

        foreach my $key (sort (keys %newplist)){
                print NEWPLIST $key . "\t" . $newplist{ $key } ."\n";
        };

        close( NEWPLIST );

	system("chmod 664 $ENV{'PXE_HOME'}/status/in_pxe.lst");

        return 0;
};


sub up_pxe_counter_file{

	my $pxe_count = `cat $ENV{'PXE_HOME'}/status/in_pxe.count`;

	chomp($pxe_count);

	$pxe_count = $pxe_count + @ip_lst;

	system("mv -f $ENV{'PXE_HOME'}/status/in_pxe.count $ENV{'PXE_HOME'}/status/in_pxe.count.backup");

	system("echo $pxe_count > $ENV{'PXE_HOME'}/status/in_pxe.count");

	system("chmod 664 $ENV{'PXE_HOME'}/status/in_pxe.count");
	
	return 0;
};

sub down_pxe_counter_file{

        my $pxe_count = `cat $ENV{'PXE_HOME'}/status/in_pxe.count`;

        chomp($pxe_count);

        $pxe_count = $pxe_count - @ip_lst;

        system("mv -f $ENV{'PXE_HOME'}/status/in_pxe.count $ENV{'PXE_HOME'}/status/in_pxe.count.backup");

        system("echo $pxe_count > $ENV{'PXE_HOME'}/status/in_pxe.count");

	system("chmod 664 $ENV{'PXE_HOME'}/status/in_pxe.count");

        return 0;
};

sub record_distro{

	if( !( -e "$ENV{'PXE_HOME'}/status/in_pxe.distro" ) ){
		system("touch $ENV{'PXE_HOME'}/status/in_pxe.distro");
	};

	open( RECORD, "< $ENV{'PXE_HOME'}/status/in_pxe.distro" ) or die $!;

	my $line;

	my %record;

	while( $line = <RECORD> ){
		chomp($line);
		if( $line =~ /^(\d+\.\d+\.\d+\.\d+)\s+(.+)\s+(.+)\s+(\d+)/ ){
			$record{ $1 } = $2 . "\t" . $3 . "\t" . $4;
		};
	};

	close( RECORD );

	for( my $i = 0; $i < @ip_lst; $i++){
		$record{ $ip_lst[$i] } = $distro_lst[$i] . "\t" . $version_lst[$i] . "\t" . $arch_lst[$i];
	};

	system("mv -f $ENV{'PXE_HOME'}/status/in_pxe.distro $ENV{'PXE_HOME'}/status/in_pxe.distro.backup");

	open( NEWRECORD, "> $ENV{'PXE_HOME'}/status/in_pxe.distro" ) or die $!;

        foreach my $key (sort (keys %record)){
                print NEWRECORD $key . "\t" . $record{ $key } ."\n";
        };

        close( NEWRECORD );

	system("chmod 664 $ENV{'PXE_HOME'}/status/in_pxe.distro");

        return 0;

};


###	ADDED 050112			TO KEEP TRACK OF WHO'S GOT WHAT MACHINES
sub record_kickstart_event{

	my ($email, $ts, $result) = @_;

	my $filename = "$ENV{'PXE_HOME'}/status/pxe_history.record";

	my $record = "\nKICKSTART RECORD\n";
	$record .= "TS\t$ts\n";
	$record .= "EMAIL\t$email\n\n";
	$record .= "$result\n";
	$record .= "END_OF_RECORD\n\n";

	system("echo \"$record\" >> $filename");

	return 0;
};


# Simple Email Function
# ($to, $from, $subject, $message)
sub sendMail {
	my ($to, $from, $subject, $message) = @_;
	my $sendmail = '/usr/lib/sendmail';

	my @recv_emails = split( /;/, $to );

	foreach my $to_who ( @recv_emails ){

		if( $to_who =~ /(.+)\@(.+)/ ){
			open(MAIL, "|$sendmail -oi -t");
			print MAIL "From: $from\n";
			print MAIL "To: $to_who\n";
			print MAIL "Subject: $subject\n\n";
			print MAIL "$message\n";
			close(MAIL);
		};
	};
		
	return 0;
};

1;



