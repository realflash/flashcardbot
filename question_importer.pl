#!/usr/bin/perl
our $VERSION = "0.1";
use open qw/:std :utf8/;	# tell perl that stdout, stdin and stderr is in utf8
use strict;

use Log::Log4perl;
use Data::Dumper;
use DBI;
use File::Basename;

use constant
{
	ERR_NO_SUCH_FILE => 2,
	ERR_NOT_A_FILE => 3,
	ERR_FILE_NOT_READABLE => 4,
};

Log::Log4perl->init(
{ 
   'log4perl.rootLogger' => 'TRACE, LOGFILE',
    'log4perl.appender.LOGFILE' => 'Log::Log4perl::Appender::Screen',
    'log4perl.appender.LOGFILE.utf8' => '1',
    'log4perl.appender.LOGFILE.layout' => 'PatternLayout',
    'log4perl.appender.LOGFILE.layout.ConversionPattern' => '%d [%c] %p - %m%n'
});

my $log = Log::Log4perl->get_logger('flashcardbot-question-importer');

# Was a file specified
printHelp() unless(defined($ARGV[0]));
# Is it readable
testFileReadable($ARGV[0]);
# Did it have right file extension
my($filename, $out_dir, $suffix) = fileparse($ARGV[0], qw(.tsv));
unless(defined($suffix))
{
	$log->fatal("File must have a .tsv extension");
	printHelp();
}

# All is well
my $topic = $filename;
$log->info("Importing questions from $filename.$suffix into question set $topic");

# Connect to the DB
my $driver   = "SQLite"; 
my $database = "flashcardbot.db";
my $dsn = "DBI:$driver:dbname=$database";
my $userid = "";
my $password = "";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1, PrintError => 0 }) or die $DBI::errstr;
$log->info("Connected to DB $database");

# Check the table for this topic exists and create if not
my $stmt = qq(SELECT name FROM sqlite_master WHERE type='table' AND name=?);
my $sth = $dbh->prepare($stmt);
my $rv = $sth->execute($topic) or die $DBI::errstr;
if($rv < 0){
	print $DBI::errstr;
}
my $table = $sth->fetchrow_hashref();
if(defined($table))
{
	$log->warn("WARNING: About to delete all existing questions in the topic $topic. Pausing 10 seconds so that you can interrupt me if you want.");
	sleep 10;
	my $stmt = qq(DELETE FROM $topic);
	my $sth = $dbh->prepare($stmt);
	my $rv = $sth->execute() or die $DBI::errstr;
	if($rv < 0)
	{
		$log->logdie("Failed to delete contents of table $topic: $DBI::errstr");
	}
	$log->debug("Emptied DB table for topic $topic");
}
else
{
	my $stmt = qq(CREATE TABLE $topic(UID INTEGER PRIMARY KEY, QUESTION TEXT NOT NULL, ANSWER TEXT NOT NULL));
	my $sth = $dbh->prepare($stmt);
	my $rv = $sth->execute() or die $DBI::errstr;
	if($rv < 0)
	{
		$log->logdie("Failed to create table user: $DBI::errstr");
	}
	if($rv > 1)
	{
		$log->logdie("Failed to create table, got more than one row updated");
	}
	$log->debug("Created a new DB table for topic $topic");
}

# Import the questions
open(IN, "<", $ARGV[0]) or die "Couldn't open file $ARGV[0]";
my @lines = <IN>;
$stmt = qq(INSERT into $topic (question, answer) VALUES (?, ?););
$sth = $dbh->prepare($stmt);
foreach my $line(@lines)
{
	my ($q, $a) = split(/\t/, $line);
	$log->trace("Q: $q");
	$log->trace("A: $a");
	my $rv = $sth->execute($q, $a) or die $DBI::errstr;
	if($rv < 0)
	{
		$log->logdie("Failed to insert new question: $DBI::errstr");
	}
	if($rv > 1)
	{
		$log->logdie("Failed to insert new question, got more than one row inserted");
	}
	# Probably went OK
	$log->debug("Added question");
}

sub printHelp
{
	$log->fatal("Help: ./script <questions-and-answers.tsv>");
}

sub testFileReadable
{
	my $f = shift;
	if(! -e $f)
	{
		$log->fatal("Required file '$f' does not exist");
		exit ERR_NO_SUCH_FILE;
	}
	if(! -f $f)
	{
		$log->fatal("Required file '$f' is not a regular file");
		exit ERR_NOT_A_FILE;
	}
	if(! -r $f)
	{
		$log->fatal("Required file '$f' is not readable");
		exit ERR_FILE_NOT_READABLE;
	}
}
