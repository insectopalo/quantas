#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use File::Basename;

use Carp;
use Data::Dumper;


my $prog = basename ($0);
my $verbose = 0;

my $base = "";

my $naString = "";

my $id2gene2symbolFile = "";

GetOptions (
	"base:s"=>\$base,
	"na-string:s"=>\$naString,
	"id2gene2symbol:s"=>\$id2gene2symbolFile,
	"v|verbose"=>\$verbose
);

if (@ARGV != 2)
{
	print "generate junction matrix\n";
	print "Usage $prog [options] <in.conf> <out.txt>\n";
	print " <in.conf> [string]: the first column is the dir or file name, and the second column is the group name\n";
	print " -base         [string] : base dir of input data\n";
	print " --na-string   [string] : na string (default:empty)\n";
	print " --id2gene2symbol [file]: mapping file of id to gene to symbol\n";
	print " -v                     : verbose\n";
	exit (1);
}

my ($configFile, $outFile) = @ARGV;

if ($base ne '')
{
	Carp::croak "dir $base does not exist\n" unless -d $base;
}

print "loading configuration file from $configFile ...\n" if $verbose;
Carp::croak "contig file $configFile does not exist\n" unless -f $configFile;
my $groups = readConfigFile ($configFile, $base);

print "done.\n" if $verbose;


print "loading mapping file of id to gene to symbol...\n" if $verbose;
my %id2gene2symbolHash;
if (-f $id2gene2symbolFile)
{
	my $fin;
	open ($fin, "<$id2gene2symbolFile") || Carp::croak "cannot open file $id2gene2symbolFile to read\n";
	while (my $line = <$fin>)
	{
		chomp $line;
		next if $line=~/^\s*$/;
		my ($id, $geneId, $symbol) = split (/\t/, $line);
		$id2gene2symbolHash{$id} = "$geneId//$symbol";
	}	

	close ($fin);
}
elsif ($id2gene2symbolFile ne '')
{
	Carp::croak "cannot open file $id2gene2symbolFile to read\n";
}


my $n = keys %id2gene2symbolHash;

print "$n mapping entries loaded\n" if $verbose;



print "loading data of individual samples ...\n" if $verbose;

my %sampleData;
my $junctionInfo;
my $nJunction = 0;
my $iter = 0;

my @groupNames = sort {$groups->{$a}->{"id"} <=> $groups->{$b}->{"id"}} keys %$groups;

foreach my $gName (@groupNames)
{
	my $samples = $groups->{$gName}->{"samples"};
	foreach my $s (@$samples)
	{
		print "$iter: group=$gName, sample=$s\n" if $verbose;
		my $inputFile = $base ne '' ? "$base/$s" : $s;

		my $sdata = readJunctionDataFile ($inputFile);
		$junctionInfo = $sdata->{"junctionInfo"};
		if ($nJunction != 0)
		{
			Carp::croak "data inconsistency detected\n" if @$junctionInfo != $nJunction;
		}
		else
		{
			$nJunction = @$junctionInfo;
		}
		$sampleData{$s} = $sdata->{"data"};
		$iter++;
	}
}

print "$iter samples, $nJunction events loaded.\n" if $verbose;


print "aggregating samples in the same group ...\n" if $verbose;


my @groupData;

for (my $g = 0; $g < @groupNames; $g++)
{
	my $gName = $groupNames[$g];
	my $samples = $groups->{$gName}->{"samples"};

	foreach my $s (@$samples)
	{
		print "sample=$s\n" if $verbose;
		my $data = $sampleData{$s};
		for (my $i = 0; $i < $nJunction; $i++)
		{
			my $d = $data->[$i];

			my $nsamples = @$d;
			for (my $j = 0; $j < @$d; $j++)
            {
                $groupData[$g][$i][$j] += $d->[$j];
            }
		}
	}
}


my $fout;

open ($fout, ">$outFile") || Carp::croak "cannot open file $outFile to write\n";

if (-f $id2gene2symbolFile)
{
	print $fout join ("\t", "#event_id", "NAME", @groupNames), "\n";
}
else
{
	print $fout join ("\t", "#event_id", @groupNames), "\n";
}


for (my $i = 0; $i < $nJunction; $i++)
{
	my @out;
	for (my $g = 0; $g < @groupNames; $g++)
	{
		my $d = $groupData[$g][$i];

		$out[$g] = $d->[0];
	}

	my $gene2symbol = exists $id2gene2symbolHash{$junctionInfo->[$i][3]} ? $id2gene2symbolHash{$junctionInfo->[$i][3]} : "NA//NA";

	if (-f $id2gene2symbolFile)
	{
		print $fout join ("\t", $junctionInfo->[$i][3], $gene2symbol, @out), "\n";
	}
	else
	{
		print $fout join ("\t", $junctionInfo->[$i][3], @out), "\n";
	}
}


close ($fout);




sub readConfigFile
{
	my ($configFile, $base) = @_;
	my $fin;
	open ($fin, "<$configFile") || Carp::croak "cannot open file $configFile to read\n";
	my $i = 0;
	my %groups;

	while (my $line = <$fin>)
	{
		chomp $line;
		next if $line=~/^\s*$/;
		next if $line=~/^\#/;
		my ($sampleName, $groupName) = split (/\t/, $line);
		$groups{$groupName}->{"id"} = $i++ unless exists $groups{$groupName};
		push @{$groups{$groupName}->{"samples"}}, $sampleName;

		my $inputFile = $base ne '' ? "$base/$sampleName" : $sampleName;

		Carp::croak "Input file $inputFile does not exist\n" unless -f $inputFile;
	}
	close ($fin);
	return \%groups;
}

sub readJunctionDataFile
{
    my ($inputFile) = @_;

    my $fin;
    my @data;
    my @junctionInfo;
    open ($fin, "<$inputFile") || Carp::croak "cannot open file $inputFile to read\n";
    while (my $line = <$fin>)
    {
        chomp $line;
        next if $line =~/^\s*$/;
        next if $line =~/^\#/;

        my @cols = split (/\t/, $line);
        my (@infoCols, @dataCols);

        @infoCols = @cols[0..5];
        $dataCols[0] = $cols[4];
		
        push @junctionInfo, \@infoCols;
        push @data, \@dataCols;
    }
    close ($fin);

    return {junctionInfo=>\@junctionInfo, data=>\@data};
}


