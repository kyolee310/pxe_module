#!/usr/bin/perl

### SOURCE : http://www.perlmonks.org/?node_id=309205

use strict;
use warnings;
use POSIX ":sys_wait_h";
use Time::HiRes qw(time sleep);
use Benchmark;
# use Benchmark ':hireswallclock';    # 5.8 and above

select(STDERR);$|=1;select(STDOUT);$|=1;   # autoflush

sub print_localtime{
        my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst)=localtime(time);
        return sprintf "[%4d-%02d-%02d %02d:%02d:%02d]", $year+1900,$mon+1,$mday,$hour,$min,$sec;
};

my $Pid;
my $Outf = "out-$$.tmp";
my $Errf = "err-$$.tmp";

my $flag_outstr = 0;
my $flag_errstr = 0;
my $recent_outstr = "";
my $recent_errstr = "";
my $recent_cmd = "";
my $cmd_count = 0;

my $cmd_elapsed_time = 0;
my $flag_killed = 0;
my $used_kill_sig = 0;

sub was_errstr{ return $flag_errstr; };
sub was_outstr{ return $flag_outstr; };
sub clear_output_flags{ $flag_outstr = 0; $flag_errstr = 0; };
sub get_recent_errstr{	return $recent_errstr;	};
sub get_recent_outstr{	return $recent_outstr;	};
sub get_recent_cmd{	return $recent_cmd;	};
sub get_cmd_count{	return $cmd_count;	};

sub get_elasped_time{	return $cmd_elapsed_time; };
sub was_killed{	return $flag_killed; };
sub clear_killed_flag{	$flag_killed = 0; };
sub get_kill_sig{ return $used_kill_sig; };

sub set_killed{
   my $k_sig = shift;
   $flag_killed = 1;
   $used_kill_sig = $k_sig;
   return 0;
};

sub record_cmd{
   my $cmd = shift;
   clear_output_flags();
   clear_killed_flag();
   $recent_cmd = $cmd;
   $cmd_count++;
   return 0;
};

sub record_output{
   my ($out, $err ) = @_;
   if( $out ne "" ){ $flag_outstr = 1; };
   $recent_outstr = $out;
   if( $err ne "" ){ $flag_errstr = 1; };
   $recent_errstr = $err;
   return 0;
}

sub cleanup {
   write_result(get_kill_sig(), 0, "null", "null");
   exit(1);
};

sub slurp_file {
   my $file = shift; local $/;
   open(my $fh, $file) or die "error:open '$file': $!";
   <$fh>;
}



sub write_result {
   my ($killsig, $elap, $user, $sys) = @_;
   my $rc  = $? >> 8;      # return code of command
   my $sig = $? & 127;     # signal it was killed with
#   warn "pid=$Pid, rc=$rc sig=$sig (killsig=$killsig)\n";
#   warn "  elapsed=$elap user=$user sys=$sys\n" if defined($elap);
   if( defined($elap) ){
	$cmd_elapsed_time = $elap;
#   	print "Elapsed Time = $elap s\n";
   };
   my $outstr = slurp_file($Outf);
   my $errstr = slurp_file($Errf);
   unlink($Outf) or die "error: unlink '$Outf': $!";
   unlink($Errf) or die "error: unlink '$Errf': $!";
#   warn "cmd stdout='$outstr'\n";
#   warn "cmd stderr='$errstr'\n";
#   print "COMMAND STDOUT\n$outstr\n";
#   print "COMMAND STRERR\n$errstr\n";
   record_output( $outstr, $errstr );
}

sub run_cmd {
   my $cmd = shift;

   # warn "\nrun_cmd '$cmd' at " . scalar(localtime) . "\n";
   # print "\n" . print_localtime()  . " COMMAND : $cmd \n";
   record_cmd( $cmd );

   my $b0 = Benchmark->new();
   my $t0 = time();

   defined($Pid = fork()) or die "error: fork: $!";

   if ($Pid == 0) {
      ### child
      $SIG{'HUP'} = \&cleanup;
      $SIG{'INT'} = \&cleanup;
      $SIG{'TERM'} = \&cleanup;
      $SIG{'ABRT'} = \&cleanup;

      open(STDOUT, '>'.$Outf) or die "error create '$Outf': $!";
      open(STDERR, '>'.$Errf) or die "error create '$Errf': $!";
      exec($cmd);
      # my @args = split(' ', $cmd); exec { $args[0] } @args;
      die "error: exec: $!";
   }

   ### parent
#   warn "in run_cmd, waiting for pid=$Pid\n";
   waitpid($Pid, 0);

   my $t1 = time();
   my $b1 = Benchmark->new();
   my $bd = timediff($b1, $b0);
   my ($real, $child_user, $child_sys) = @$bd[0,3,4];

   write_result(0, $t1 - $t0, $child_user, $child_sys);

}

# Run command $cmd, timing out after $timeout seconds.
# See Perl Cookbook 2nd edition, Recipe 16.21
# See also perlfaq8 "How do I timeout a slow event".
# Return 1 if $cmd run ok, 0 if timed out.
sub run_for {
   my ($cmd, $timeout) = @_;
   my $diestr = 0;

   eval {
      local $SIG{ALRM} = sub { die "alarm clock restart" };
      alarm($timeout);    # schedule alarm in $timeout seconds
      eval { run_cmd($cmd) };
      $diestr = $@ if $@;
      alarm(0);           # cancel the alarm
   };

   $diestr = $@ if $@;
   alarm(0);              # race condition protection

   return 1 unless $diestr;
   return 0 if $diestr =~ /alarm clock restart/;

   die "ERROR: $!\n$diestr\n";
}

sub kill_it
{
#   warn "kill_it: pid=$Pid\n";
   kill(0, $Pid) or warn("pid $Pid is not alive\n"), return;

   my $waitpid; my $killsig = 15;
   kill($killsig, $Pid); sleep(0.1);

   for (1..3) {
      $waitpid = waitpid($Pid, &WNOHANG);
      last if $waitpid == $Pid;
      sleep(1);
   }

   if ($waitpid != $Pid && kill(0, $Pid)) {
      $killsig = 9;
      warn "pid $Pid not responding, resorting to kill 9\n";
      kill($killsig, $Pid);
      waitpid($Pid, 0);
   }

   set_killed($killsig);
#   write_result($killsig);
    return 0;
}

sub timed_run{
	my ($cmd, $timeout) = @_;
	
	my $result = run_for($cmd, $timeout); 
	if( $result == 0 ){
		kill_it();
		write_result(get_kill_sig(), 0, "null", "null");
		return 1;
	};
	return 0;
}

sub handle_timed_run{
	my ($outfile, $errfile) = @_;
	open( OUT, ">>$outfile" ) or die $!;
	open( ERR, ">>$errfile" ) or die $!;
	print OUT "\nCOMMAND :: " . get_recent_cmd() . "\n";
	print ERR "\nCOMMAND :: " . get_recent_cmd() . "\n";
        if( was_outstr() ){
                print OUT "STDOUT ::\n" . get_recent_outstr() . "\n";
        };
        if( was_errstr() ){
                print ERR "STDERR ::\n" . get_recent_errstr() . "\n";
        };
        #if( was_killed() ){
        #        print "KILLSIG :: " . get_kill_sig() . "\n";
        #};
	close(OUT);
	close(ERR);
	return 0;
};

1;

############################################################

#my @cmds = (
#   'ls -l',
#   'sleep 15',
#   'sleep 4',
#   'echo hello-stdout; echo hello-stderr >&2',
#);

#for my $cmd (@cmds) { 

#	timed_run( $cmd, 7 );
#	print "COMMAND :: " . get_recent_cmd() . "\n";
#	if( was_outstr() ){
#		print "STDOUT :: " . get_recent_outstr() . "\n";
#	};
#	if( was_errstr() ){
#		print "STDERR :: " . get_recent_errstr() . "\n";
#	};
#	if( was_killed() ){
#		print "KILLSIG :: " . get_kill_sig() . "\n";
#	};
#
#run_for($cmd, 10) or kill_it() 
#
#}

1;

