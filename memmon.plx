#!/data/data/com.termux/files/usr/bin/perl
#memmon.plx
# A little dæmon for running in Termux (https://github.com/termux/)
# that pops up a notification with stats on current memory usage.
# Also includes a button for turning on and off a swapfile.
use warnings;
use strict;

my $notifid = "VIGoV_MemMon";
my $total;
my $free;
my $percentage;
my $shared;
my $buffers;
my $cached;
my $notifcontent;

my $swaptot;
my $swapfree;
my $swapperc;

my $swapstatcom = "on";

while(1) {
	sleep 1;
	unless(open FREEFILE, "free -m|") {
		if(open NOTIFFILE, "| termux-notification --id ${notifid}_Err --title 'RAM Monitor Error'") {
			print NOTIFFILE "Unable to get output of 'free -m': $!\n";
			close(NOTIFFILE);
		} else {
			warn "Unable to read output of 'free -m' or create a notification to explain why!";
		}
	}
	while(<FREEFILE>){
		if(/^Mem/) {
			($total,$free,$shared,$buffers,$cached) = /^Mem:\s*(\d*)\s*\d*\s*(\d*)\s*(\d*)\s*(\d*)\s*(\d*)$/;
		} elsif(/^Swap/) {
			($swaptot,$swapfree) = /^Swap:\s*(\d*)\s*\d*\s*(\d*)$/;
		}
	}
	close(FREEFILE);
	$percentage = sprintf('%.2f',100 * $free / $total);
	if($swaptot) {
		$swapperc = sprintf('%.2f',100 * $swapfree / $swaptot);
		$swapstatcom = "off";
		$notifcontent = <<EOF;
$free MB of $total MB RAM free ($percentage\%)
$swapfree MB of $swaptot MB swap free ($swapperc\%)
($shared MB shared, $buffers MB in buffers, $cached MB cached)
EOF
	} else {
		$swapstatcom = "on";
		$notifcontent = <<EOF;
$free MB of $total MB RAM free ($percentage\%)
($shared MB shared, $buffers MB in buffers, $cached MB cached)
EOF
	}
	# Note on button1:
	# This assumes you've got a swap file in your home directory,
	# called "swapfile1", created as per the instructions at
	# https://www.cyberciti.biz/faq/linux-add-a-swap-file-howto/
	# or some such, and that you're using the Termux sudo script
	# (https://github.com/st42/termux-sudo).
	# Your mileage may vary on how well this works. Personally I
	# haven't found that it improves matters at all (FairPhone 2
	# with self-built LineageOS 14.1)
	if(open NOTIFFILE, "| termux-notification --priority min --button1 'Swap $swapstatcom' --button1-action 'sudo swap$swapstatcom ~/swapfile1' --id $notifid --on-delete 'kill $$' --title '$percentage\% RAM free'"){
		print NOTIFFILE $notifcontent;
		close(NOTIFFILE);
	} else {
		warn("Unable to open pipe to termux-notification!");
	}
}
