#!/usr/bin/perl
#tracereport.plx
# An attempt to take strace output and put it into a spreadsheet using LibreOffice Calc...
# As featured in my blog post https://www.vigovproductions.net/interactive/automating-libreoffice-using-perl-and-uno.html
# See there for information about what exactly this does and how to make it work.
use warnings;
use strict;
use OpenOffice::UNO;

# Check if we have a spreadsheet name.
if (scalar(@ARGV) < 1) {
	die("You need to specify a spreadsheet path (absolute!) as an argument!\n");
}
my $docname = shift @ARGV;
# Next look for a directory of images.
my $imgdir;
if (scalar(@ARGV) and -d($ARGV[0])) {
	$imgdir = shift @ARGV;
} else {
	use Cwd;
	$imgdir = cwd();
}

my @pics;
my @pictimestamps;

# Check for images in our directory.
open FILELIST, "ls -gt --time-style=\"+%X.%N\" $imgdir/{*.png,*.gif,*.jpg} |";
while(<FILELIST>) {
	my ($perms,$num,$group,$size,$timestamp,$filepath) =
		/^([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*(.*)$/;
	# ls sorts by newest first, so unshift to get oldest first.
	unshift(@pictimestamps,makeseconds($timestamp));
	unshift(@pics,$filepath);
}
close FILELIST;

# connect to the OpenOffice.org server
my $uno = OpenOffice::UNO->new;
my $cxt = $uno->createInitialComponentContext;
my $sm  = $cxt->getServiceManager;
my $resolver = $sm->createInstanceWithContext("com.sun.star.bridge.UnoUrlResolver", $cxt);
my $rsm = $resolver->resolve("uno:socket,host=localhost,port=8100;urp;StarOffice.ServiceManager");

# get an instance of the Desktop service
my $rc = $rsm->getPropertyValue("DefaultContext");
my $desktop = $rsm->createInstanceWithContext("com.sun.star.frame.Desktop", $rc);
# and of the Dispatcher service
my $dispatcher = $rsm->createInstanceWithContext("com.sun.star.frame.DispatchHelper", $rc);

# create a name/value pair to be used in opening the spreadsheet
my $open_args = createUnoArgSet($uno, {Hidden => "False"});

# open a spreadsheet
my $sdoc = $desktop->loadComponentFromURL("private:factory/scalc","_blank", 0, $open_args);

# Start recording trace info.
my @trace_output_lines;
my @unfinished_output_lines;
my $mostparams = 0;

while(my $line = <>) {
	# First extract the PID and timestamp.
	$line =~ s/^(\d*)\s*([\d:\.]*)\s*//;
	my $pid = $1;
	my $timestamp = $2;

	# Next figure out if it's unfinished.
	if($line =~ s/\s*<unfinished\s\.\.\.>$//) {
		# It's an unfinished line. Record it, along with its call and PID.
		$line =~ /^([^\(]*)\(/;
		my $call = $1;
		chomp($line);
		push @unfinished_output_lines,
			{call => $call,
			line => $line,
			pid => $pid};
	} else {
		# Not unfinished. Is it resumed?
		if($line =~ s/^<\.\.\.\s(.*)\sresumed>//) {
			# This is the resumption of an unfinished line.
			# Identify its call and PID and match it to one we recorded earlier.
			my $call = $1;
			# Loop through list of unfinished lines.
			my $index = 0;
			$index++ until (($unfinished_output_lines[$index]->{"pid"} eq $pid and
				$unfinished_output_lines[$index]->{"call"} eq $call) or
				$index >= $#unfinished_output_lines); # Prevent infinities!
			# Concatenate previous line with this one.
			$line = $unfinished_output_lines[$index]->{"line"}.$line;
			# Take it away from the unfinished list, since it's finished now!
			splice(@unfinished_output_lines, $index, 1);
		}
		
		# Next parse the full line.
		my $parsedline;
		if($line =~ /^([^\(]*)\((.*)\)\s*=\s*(-?[\d\?]+.*?)$/) {
			my $call = $1;
			my $params = $2;
			my $result = $3;
			# Split up params into an array.
			# Treat structures as single params.
			my @pararray = parseparams($params);
			# Put together a nice structure to push onto our list of lines.
			$parsedline =
				{pid => $pid,
				timestamp => $timestamp,
				seconds => makeseconds($timestamp),
				call => $call,
				params => [@pararray],
				result => $result};
			# Determine the longest list of parameters we have.
			$mostparams = scalar(@pararray) if scalar(@pararray) > $mostparams;
		} else {
			# Unparseable.
			chomp($line);
			$parsedline =
				{pid => $pid,
				timestamp => $timestamp,
				seconds => makeseconds($timestamp),
				rawline => $line};
		}
		
		# Next see if there are any images to put in!
		while (scalar @pics and ($pictimestamps[0] < $parsedline->{"seconds"})) {
			push @trace_output_lines,
				{image => $pics[0]};
			# Clean out the arrays as we're going, so we can always check entry zero.
			shift @pics;
			shift @pictimestamps;
		}
		# Now stick in the actual trace output line.
		push @trace_output_lines, $parsedline;
	}
}

# Add in the header line.
unshift @trace_output_lines,
	{pid => "PID",
	timestamp => "Timestamp",
	call => "Call",
	result => "Result",
	params => [map {"Parameter $_"} (1..$mostparams)]};

# Maximum number of rows…
warn "Too many lines in this trace! The report will be truncated!" if (@trace_output_lines > 2**20);

# Get access to our controller.
my $controller = $sdoc->getCurrentController();
# Freeze the header row...
$controller->freezeAtPosition(0,1);

# Get access to our first (and only) spreadsheet.
my $sheet = $sdoc->getSheets()->getByIndex(0);
$sheet->setName("Trace Report");
# Get access to the draw page too, to manage the "shapes" (images).
my $drawpage = $sheet->getDrawPage();

# Go through the rows.
my $rightmostcol = 4 + $mostparams;
$rightmostcol = 1023 if $rightmostcol > 1023;
for my $lineindex (0..$#trace_output_lines) {
	# Have we reached the end of the spreadsheet
	if ($lineindex == (2**20 - 1) and $#trace_output_lines > $lineindex) {
		# Explain what happened…
		$sheet->getCellByPosition(0,$lineindex)->setString("Report truncated!");
		$controller->select($sheet->getCellRangeByPosition(0,$lineindex,$rightmostcol,$lineindex));
		$dispatcher->executeDispatch($controller,".uno:MergeCells","",0,[]);
		# We're done here.
		last;
	}

	# Otherwise tutto va bene.
	my %linehash = %{$trace_output_lines[$lineindex]};
	if (defined $linehash{"image"}) {
		# This "line" is a pic.
		# Go to the cell we want to put it at.
		$controller->select($sheet->getCellByPosition(0,$lineindex));
		# Now execute the dispatch to insert the picture.
		# First it wants to know the filter for whatever reason.
		my $filter;
		if ($linehash{"image"} =~ /png$/) {
			$filter = "PNG - Portable Network Graphic";
		} elsif ($linehash{"image"} =~ /gif$/) {
			$filter = "GIF - Graphics Interchange Format";
		} elsif ($linehash{"image"} =~ /jpg$/) {
			$filter = "JPEG - Joint Photographic Experts Group";
		}
		$dispatcher->executeDispatch($controller->getFrame(),".uno:InsertGraphic","",0,createUnoArgSet($uno, {
					FileName => "file://".$linehash{"image"},
					FilterName => $filter,
					AsLink => "False"}));
		# Grab the newest-inserted graphic.
		my $graphicheight = $drawpage->getByIndex($drawpage->getCount()-1)->getSize()->Height;
		# Now get the row and adjust its height.
		my $row = $sheet->getRows()->getByIndex($lineindex);
		setUnoProps($row,{Height=>$graphicheight});
		# Now, none of the rest of this stuff is relevant.
		next;
	}
	$sheet->getCellByPosition(0,$lineindex)->setString($linehash{"pid"});
	$sheet->getCellByPosition(1,$lineindex)->setString($linehash{"timestamp"});
	# Now, was the line parseable or not?
	if (defined $linehash{"rawline"}) {
		# Just throw in the entire line.
		$sheet->getCellByPosition(2,$lineindex)->setString($linehash{"rawline"});
		# Now merge remaining cells. Need to dispatch this too it seems.
		$controller->select($sheet->getCellRangeByPosition(2,$lineindex,$rightmostcol,$lineindex));
		$dispatcher->executeDispatch($controller,".uno:MergeCells","",0,[]);
	} else {
		$sheet->getCellByPosition(2,$lineindex)->setString($linehash{"call"});
		$sheet->getCellByPosition(3,$lineindex)->setString($linehash{"result"});
		my @pararray = @{$linehash{"params"}};
		for my $parindex (0..$#pararray) {
			if($parindex == 1019 and $#pararray > 1019) {
				# Max column index is 1023!
				$sheet->getCellByPosition(4+$parindex,$lineindex)->setString("etc.");
				last;
			}
			last if $parindex > 1019;
			my $param = '';
			defined $pararray[$parindex] and $param = $pararray[$parindex];
			# Eval any quote blocks!
			for my $quoteblock ($param =~ /("[^"]*")/g) {
				# Get rid of sigils that confuse Perl.
				$quoteblock =~ s/\$/\\\$/g;
				$quoteblock =~ s/\@/\\\@/g;
				$quoteblock =~ s/\%/\\\%/g;
				# Evaluate
				my $evaled = eval $quoteblock;
				$param =~ s/("[^"]*")/$evaled/ if defined $evaled;
			}
			$sheet->getCellByPosition(4+$parindex,$lineindex)->setString($param);
		}
	}
}

# Make the columns optimal-width.
for my $colindex (0..$rightmostcol) {
	setUnoProps($sheet->getColumns()->getByIndex($colindex),{OptimalWidth=>"True"});
}

# save the spreadsheet
my $save_args = createUnoArgSet($uno, {Overwrite => "True",
					FilterName => "calc8"});
$sdoc->storeAsURL("file://" . $docname, $save_args);

# close the spreadsheet
$sdoc->dispose();

###############
# SUBROUTINES #
###############
sub makeseconds {
	my $timestamp = shift;
	my ($hours, $minutes, $floatseconds) = ($timestamp =~ /(\d\d):(\d\d):(.*)/);
	return $hours * 3600 + $minutes * 60 + $floatseconds;
}

sub createUnoObj {
	# Take a number or boolean and turn it into an appropriate
	# Uno object. Useful for setting properties and argsets.
	my $value = shift;
	# First of all, is it already an object?
	if(ref($value) =~ /^OpenOffice::UNO/) {
		return $value; # Send it on its merry way!
	}

	# Okay, let's see what to do with it...
	unless ($value & ~$value) {
		# Numeric.
		# Is it a float?
		if(int($value) - $value) {
			# Just send it...
			return $value;
		} elsif (abs($value) < 2**16) {
			# It's an int...
			return OpenOffice::UNO::Int32->new($value);
		} else { 
			# Won't fit in an Int32.
			return OpenOffice::UNO::Int64->new($value);
		}
	} else {
		# String...
		# Okay, is it a Boolean?
		if($value eq "True") {
			return OpenOffice::UNO::Boolean->new(1);
		} elsif($value eq "False") {
			return OpenOffice::UNO::Boolean->new(0);
		} else {
			# Okay, it's just a string.
			return $value;
		}
	}
}

sub createUnoArgSet {
	# Takes UNO object, plus a hash (or reference thereto)
	# and returns a reference to an array of PropertyValues.
	my $uno = shift;
	die "createUnoArgSet called without reference to UNO object!"
		unless ref($uno) eq "OpenOffice::UNO";

	my %inputhash;
	my @outputlist;

	if (scalar(@_) == 1) {
		# Got a scalar - must be a reference!
		%inputhash = %{$_[0]};
	} else {
		# Got more than one value - assume a hash.
		%inputhash = @_;
	}

	for my $arg (keys %inputhash) {
		my $pv = $uno->createIdlStruct("com.sun.star.beans.PropertyValue");
		$pv->Name($arg);
		$pv->Value(createUnoObj($inputhash{$arg}));
		push @outputlist, $pv;
	}

	return \@outputlist;
}

sub unwrapUnoArgSet {
	# Takes a reference to an array of PropertyValues
	# and returns a reference to a hash.
	my @pvset = @{$_[0]};
	my %outputhash;

	for my $pv (@pvset) {
		$outputhash{$pv->Name()} = $pv->Value();
	}

	return \%outputhash;
}

sub setUnoProps {
	# Wrapper of setPropertyValue that sends nice UNO objects.
	my $unoObj = shift;
	die "setUnoProps called without reference to an UNO struct/interface/any!"
		unless ref($uno) =~ /^OpenOffice::UNO/;

	my %inputhash;

	if (scalar(@_) == 1) {
		# Got a scalar - must be a reference!
		%inputhash = %{$_[0]};
	} else {
		# Got more than one value - assume a hash.
		%inputhash = @_;
	}

	for my $arg (keys %inputhash) {
		$unoObj->setPropertyValue($arg,createUnoObj($inputhash{$arg}));
	}
}

sub parseparams {
	# Split parameters from calls, respecting structures 
	# enclosed by brackets/parentheses/braces.
	# Mostly based on https://stackoverflow.com/a/5052668
	my ($string) = @_;
	my @fields;

	my @comma_separated = split(/,\s*/, $string);

	my @to_be_joined;
	my $depth = 0;
	foreach my $field (@comma_separated) {
		my @brackets = $field =~ /(\(|\)|\[|\]|\{|\})/g;
		foreach (@brackets) {
			$depth++ if /\(|\[|\{/;
			$depth-- if /\)|\]|\}/;
		}

		if ($depth == 0) {
			push @fields, join(", ", @to_be_joined, $field);
			@to_be_joined = ();
		} else {
			push @to_be_joined, $field;
		}
	}

	return @fields;
}
