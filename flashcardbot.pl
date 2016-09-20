#!/usr/bin/perl
our $VERSION = "0.1";
use open qw/:std :utf8/;	# tell perl that stdout, stdin and stderr is in utf8
use strict;

use Log::Log4perl;
use Slack::RTM::Bot;
use Data::Dumper;
use DBI;

Log::Log4perl->init(
{ 
   'log4perl.rootLogger' => 'TRACE, LOGFILE',
#    'log4perl.appender.LOGFILE' => 'Log::Log4perl::Appender::File',
#    'log4perl.appender.LOGFILE.filename' => '/home/igibbs/advert_poster.log',
 #   'log4perl.appender.LOGFILE.mode' => 'append',
    'log4perl.appender.LOGFILE' => 'Log::Log4perl::Appender::Screen',
    'log4perl.appender.LOGFILE.utf8' => '1',
    'log4perl.appender.LOGFILE.layout' => 'PatternLayout',
    'log4perl.appender.LOGFILE.layout.ConversionPattern' => '%d [%c] %p - %m%n'
});

my $log = Log::Log4perl->get_logger('flashcardbot');
my $bot = Slack::RTM::Bot->new(token => $ENV{SLACK_TOKEN});
my $bot_id = 'U2CBQUXL7';
my $bot_name = 'flashcardbot';
my @commands = qw(echo help testme donttestme);

my $driver   = "SQLite"; 
my $database = "flashcardbot.db";
my $dsn = "DBI:$driver:dbname=$database";
my $userid = "";
my $password = "";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1, PrintError => 0 }) or die $DBI::errstr;
$log->info("Connected to DB $database");

# Simple echo 
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^<\@$bot_id> echo/i,						# Mention
    }, sub { echo(filterMessageText(@_)) unless iSaidIt(@_)});
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^echo/i,		
        channel => qr/^\@/i,											# DM
    }, sub { echo(filterMessageText(@_)) unless iSaidIt(@_)});
# Help
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^<\@$bot_id> help\w*/i,							# Mention
    }, sub { help(filterMessageText(@_)) unless iSaidIt(@_)});
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^help\w*/i,				
        channel => qr/^\@/i,											# DM
    }, sub { help(filterMessageText(@_)) unless iSaidIt(@_)});
# Start testing
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^<\@$bot_id> (testoff)|(stoptest)|(donttestme)|(shutup)/i,	# Mention				
    }, sub { stopTest(filterMessageText(@_)) unless iSaidIt(@_)});
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^(testoff)|(stoptest)|(donttestme)|(shutup)/i,				
        channel => qr/^\@/i,											# DM
    }, sub { stopTest(filterMessageText(@_)) unless iSaidIt(@_)});
# Stop testing
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^(test)|(teston)|(starttest)|(testme)/i,			# Mention		
        channel => qr/^\@/i,											# DM
    }, sub { startTest(filterMessageText(@_)) unless iSaidIt(@_) || alreadyHandled(@_) });
# Otherwise
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        text    => qr/^<\@$bot_id>/i,									# Mentioned
    }, sub { commandNotKnown(filterMessageText(@_)) unless iSaidIt(@_) || alreadyHandled(@_) });
$bot->on({
		team	=> qr/.*/,												# Filters out 'ok' events that come back after posting a message
        channel    => qr/^\@/i,											# DM
    }, sub { commandNotKnown(filterMessageText(@_)) unless iSaidIt(@_) || alreadyHandled(@_) });

$bot->start_RTM;

while(1)
{
#	$log->trace("Waking up");
	my $users = getUsers();
#	print Dumper $users;
#	$log->trace("Going to sleep");
	sleep 5;
}	

############ FUNCTIONS #######################

sub echo
{
	my ($event) = @_;

	$log->info("Echo: $event->{text}");
	print Dumper $event;
    $bot->say(channel => $event->{'channel'}, text => $event->{'text_filtered'});
    $_[0]->{'responded'} = 1;
}

sub startTest
{
	my ($event) = @_;

    $log->info("Test requested by $event->{'user'}: $event->{text}");
	setTestStatus($event->{'user'}, $event->{'team'}, 1, "aircraft_checklists");
    $bot->say(channel => "@".$event->{'user'}, text => "I will start testing you from now, at random times.");
    $_[0]->{'responded'} = 1;
}	

sub stopTest
{
	my ($event) = @_;

    $log->info("Test stop requested by $event->{'user'}: $event->{text}");
	setTestStatus($event->{'user'}, $event->{'team'}, 0);
    $bot->say(channel => "@".$event->{'user'}, text => "I will stop testing you. I hope I was helpful.");
    $_[0]->{'responded'} = 1;
}	

sub setTestStatus
{
	my $user = shift;
	my $team = shift;
	my $status = shift;
	my $topic = shift;
		
    my $db_user = getUser($user, $team);
	unless(defined($db_user))
	{
		$log->debug("User $team/$user is new to me");
		my $stmt = qq(INSERT into USERS (user, team, topic, enabled) VALUES (?, ?, ?, ?););
		my $sth = $dbh->prepare($stmt);
		my $rv = $sth->execute($user, $team, $topic, $status) or die $DBI::errstr;
		if($rv < 0)
		{
			$log->logdie("Failed to insert new user: $DBI::errstr");
		}
		if($rv > 1)
		{
			$log->logdie("Failed to insert new user, got more than one row inserted");
		}
		# Probably went OK
		return;
	}
	else
	{
		$log->debug("User $user is an existing user");
		my $rv;
		if(defined($topic))
		{
			my $stmt = qq(UPDATE USERS set topic = ?, enabled = ? WHERE UID = ?;);
			my $sth = $dbh->prepare($stmt);
			$rv = $sth->execute($topic, $status, $db_user->{'UID'}) or die $DBI::errstr;
		}
		else
		{
			my $stmt = qq(UPDATE USERS set enabled = ? WHERE USER = ?;);
			my $sth = $dbh->prepare($stmt);
			$rv = $sth->execute($status, $user) or die $DBI::errstr;
		}
			
		if($rv < 0)
		{
			$log->logdie("Failed to update user: $DBI::errstr");
		}
		if($rv > 1)
		{
			$log->logdie("Failed to update user, got more than one row updated");
		}
		# Probably went OK
		$log->debug("Set enabled to $status and topic to $topic");
		return;
		
	}
	return;
}

sub getUser
{
	my $user = shift;
	my $team = shift;
	
	my $stmt = qq(SELECT * from USERS WHERE user = ? AND team = ?;);
	my $sth = $dbh->prepare($stmt);
	my $rv = $sth->execute($user, $team) or die $DBI::errstr;
	if($rv < 0){
		print $DBI::errstr;
	}
	my $user = $sth->fetchrow_hashref();
	return $user;
}	

sub getUsers
{
	my $user = shift;
	
	my $stmt = qq(SELECT * from USERS;);
	my $sth = $dbh->prepare($stmt);
	my $rv = $sth->execute() or die $DBI::errstr;
	if($rv < 0){
		print $DBI::errstr;
	}
	my $users = $sth->fetchall_arrayref({});
	return $users;
}	

sub help
{
	my ($event) = @_;

    $log->info("Help requested: $event->{text}");
    $bot->say(channel => "@".$event->{'user'}, text => "I know these commands: ".stringifyList(\@commands));
    $_[0]->{'responded'} = 1;
}	

sub commandNotKnown
{
	my ($event) = @_;
	print Dumper $event;
    $log->info("Command not known: $event->{text}");
    $bot->say(channel => $event->{'channel'}, text => "I'm sorry, I don't know that command. Try 'help'");
}

sub iSaidIt
{
	my $event = shift;
	
	$log->trace("Message posted by ".$event->{'user'});
	return 1 if $event->{'user'} =~ /^flashcardbot$/;
	return 0;
}

sub alreadyHandled
{
	my $event = shift;
	
	return 1 if $event->{'responded'};					# One of the other event handlers already dealt with this message
}

sub filterMessageText
{
	my $event = shift;

	# Copy the text so that we can mess with it
	$event->{'text_filtered'} = $event->{'text'};
	# If it was a mention rather than a DM get rid of that from the text
	$event->{'text_filtered'} =~ /^(<[@]$bot_id> )(.*)/;
	$event->{'text_filtered'} = $2 if defined($1);
	# We don't need the commands any more
	foreach my $cmd (@commands)
	{
		$event->{'text_filtered'} =~ /^($cmd )(.*)/i;
		$event->{'text_filtered'} = $2 if defined($1);
	}
	return $event;
}

sub stringifyList
{
	my $list = shift;

	my $r = "";
	foreach my $v (@$list)
	{
		$r = $r."$v ";
	}

	return $r;
}
