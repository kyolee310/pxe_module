#!/usr/bin/perl
use strict;
use Cwd qw(chdir);

$ENV{'TEST_HOME'} = "/home/qa-server";
$ENV{'PXE_HOME'} = $ENV{'TEST_HOME'} . "/pxe_module";

if( @ARGV < 1 ){
	print "ERROR !! USAGE : ./add_new_machine.pl <MACHINE NAME> <p.IP> <p.MAC> <i.IP> <i.MAC>\n";
	exit(1);
};

my $newname = $ARGV[0];
my $newip = $ARGV[1];
my $newmac = lc($ARGV[2]);
my $newip_2 = $ARGV[3];
my $newmac_2 = lc($ARGV[4]);

print "Will add Machine $newname Primary Device [ $newip, $newmac ] and IDRAC Device [ $newip_2, $newmac_2 ] to the KICKSTART SERVICE\n";

print "\n";

### Don't think it's necessary
#obtain_the_lock();

validate_inputs();
add_new_machine();
give_dhcp_guide();

#release_the_lock();

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

sub validate_inputs{
	return 0;
};

sub add_new_machine{

	my $nu_line = $newname . "\t" . $newip . "\t" . $newmac;

	my $allowed_file = "$ENV{'PXE_HOME'}/maps/mac_to_ip.allowed";
	my $map_file = "$ENV{'PXE_HOME'}/maps/mac_to_ip.map";
	my $idrac_map = "$ENV{'PXE_HOME'}/maps/ip_to_idrac.map";
	my $in_pxe_lst = "$ENV{'PXE_HOME'}/status/in_pxe.lst";

	print "\n";
	print "Adding the line\n\n";
	print "$nu_line\n";
	print "\nto\n\n";
	print "$allowed_file\t";
	print "and\t";
	print "$map_file\n";

	system("echo \"$nu_line\"  >> $allowed_file");
	system("echo \"$nu_line\"  >> $map_file");

	my $nunu_line = $newip . "\t" . $newip_2;

	print "\n\nAdding the line\n\n";
	print "$nunu_line\n";
	print "\nto\n\n";
        print "$idrac_map\n";

	system("echo \"$nunu_line\"  >> $idrac_map");

	my $more_line = $newip . "\tUP";

	print "\n\nAdding the line\n\n";
        print "$more_line\n";
        print "\nto\n\n";
        print "$in_pxe_lst\n";

        system("echo \"$more_line\"  >> $in_pxe_lst");

	return 0;
};


sub give_dhcp_guide{

	print "\n\n";
	print "<font color=red>";
	print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
	print "FINAL STEP. ADD THE LINES BELOW TO castillian's /etc/dhcp/dhcp.conf and restart dhcp service\n";
	print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
	print "\n\n";
	print "</font>";
	print "<font color=blue>";
	print "host " . $newname . " {\n";
	print "\thardware ethernet " . uc($newmac) . ";\n";
	print "\tfixed-address " . $newip . ";\n";
	print "\tfilename \"pxelinux.0\";\n";
	print "\tnext-server 192.168.51.150;\n";
	print "}\n";
	print "\n";
	print "host " . $newname . "-LOM {\n";
	print "\thardware ethernet " . uc($newmac_2) . ";\n";
	print "\tfixed-address " . $newip_2 . ";\n";
	print "}\n";
	print "\n";
	print "</font>";
	print "\n";

	return 0;
};
