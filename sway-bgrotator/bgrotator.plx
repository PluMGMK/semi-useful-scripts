#!/usr/bin/perl
# bgrotator.plx
# Change the Sway (https://github.com/swaywm/sway) wallpaper at regular intervals.
# The list of wallpapers to use is taken from a file given on the command line.
# Or, if you use GNOME, it can be provided by the GSettings database for Backslide
# (https://extensions.gnome.org/extension/543/backslide/).
use warnings;
use strict;
 
use Getopt::Long;

my $file;
my $output;
my $interval;
my $randomize;
my $backslide;
GetOptions(
	"file=s" => \$file,
	"output=s" => \$output,
	"interval:f" => \$interval,
	"randomize!" => \$randomize,
	"use-backslide" => \$backslide
);

sub printusage {
        print <<EOF;
Usage: $0 [--interval <seconds>] [--(no)randomize] --file <filename> [--output <output>]
   OR: $0 --use-backslide [--(no)randomize] [--output <output>]
        The wallpaper changes every <seconds> seconds, which defaults to 30.
        If randomize is specified, the wallpapers will be displayed in a random order.
        The file <filename> should contain a list of wallpapers.
	If use-backslide is specified, the wallpaper list and interval are taken from the GSettings Schema for BackSlide instead.
	<output> is the sway output on which to change the wallpaper. (See swaymsg -t get_outputs for a list.) If unspecified, all outputs are used.

EOF
}

#die "Coming soon!\n" if $backslide;

# What output?
unless ($output) {
	print "No output specified, using all.\n";
	$output = '*';
}

my @wallpapers;
unless ($backslide) {
	# We do need a filename.
	unless ($file) {
		printusage();
		die "Please specify a filename!\n";
	}

	# Try to open our file.
	open(LIST, $file) or die "Couldn't open $file!\n";
	# Read in our list of wallpapers.
	@wallpapers = <LIST>;
	# Tidy up.
	close LIST;
} else {
	# We're going to use GSettings to query the parameters used by BackSlide.
	my $gsettings="gsettings";
	my $schemadir='--schemadir ~/.local/share/gnome-shell/extensions/backslide@codeisland.org/schemas/';
	my $command  ="get";
        my $schema   ="org.gnome.shell.extensions.backslide";
	# First get the interval.
	my $key      ="delay";
	open(TIME, $gsettings." ".$schemadir." ".$command." ".$schema." ".$key." |") or die "Unable to query GSettings key $key in schema $schema.\n";
	$interval = <TIME>;
	$interval *= 60; # It's in minutes.
	close TIME;
	
	# Next the list of actual wallpapers.
	$key="image-list";
	open(LIST, $gsettings." ".$schemadir." ".$command." ".$schema." ".$key." |") or die "Unable to query GSettings key $key in schema $schema.\n";
	my $list = <LIST>;
	# Strip off enclosing square brackets.
	$list =~ /^\[(.*)\]$/;
	# Split into separate single-quote-enclosed paths.
	my @quotedlist = split(/,\s/, $1);
	# Finally remove quotes.
	foreach (@quotedlist) {
		$_ =~ /'(.*)'/;
		printf "Wallpaper at $1.\n";
		push(@wallpapers, $1);
	}
	close LIST;
}

# Default interval.
$interval = 30 unless ($interval && ($interval > 0));

my $wallindex = 0; # If they're not random keep track of the order.
# Go into our loop until we can no longer communicate with sway.
while (!system("swaymsg")) { #system() is 0 on success, and swaymsg always succeeds with no command, if sway is running.
	$wallindex = rand(@wallpapers) if $randomize;
	`swaymsg -t command "output $output bg $wallpapers[$wallindex] fill"`;
	
	# Increment our index, and loop it.
	$wallindex++;
	$wallindex = 0 if ($wallindex >= @wallpapers);

	# Wait.
	sleep $interval;
}
