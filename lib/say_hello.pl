#!/usr/bin/perl

use strict;

$ENV{'MAIL_DIR'} = "/home/mailman";

my $my_ip = $ENV{'SSH_CLIENT'};

my $distro = "";
my $source = "";
my $roll = "";

my $report_time = print_time();

my $log_line = $report_time . "\t" . $my_ip;

system("echo $log_line >> $ENV{'MAIL_DIR'}/mailbox/contact_records.log");


if( $my_ip =~ /(.+)\s(\d+)\s(\d+)/ ){
	$my_ip = $1;
}else{
	$my_ip = "UNKNOWN";
};

# log
if( -e "$ENV{'MAIL_DIR'}/mailbox/$my_ip"){
	my $temp_dup = $report_time . "DUP";
	system("echo $temp_dup >> $ENV{'MAIL_DIR'}/mailbox/$my_ip");
	exit(0);
};


system("touch $ENV{'MAIL_DIR'}/mailbox/$my_ip");

system("chmod 664 $ENV{'MAIL_DIR'}/mailbox/$my_ip");

exit(0);

1;

sub print_time{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst)=localtime(time);
        my $this_time = sprintf "[%4d-%02d-%02d %02d:%02d:%02d]\t", $year+1900,$mon+1,$mday,$hour,$min,$sec;
	return $this_time;
};


