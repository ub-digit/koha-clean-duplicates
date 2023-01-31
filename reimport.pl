use strict;

use Encode qw(encode);
use MARC::Batch;
use Data::Dumper;
use File::Copy;

my $basedir = '/var/lib/koha/koha/import_failed_records/multiple_matches';

opendir(DIR, $basedir);
my @files = grep(/\.marc$/, readdir(DIR));
closedir(DIR);

my @libris_records;
my @partially_matching_records;
my @non_matching_records;
foreach my $file (@files) {
	my $batch = MARC::Batch->new('USMARC', "$basedir/$file");
	$batch->strict_on();
	my $libris_id;
	my $libris_id_035a;
	while(my $record = $batch->next()) {
		if (!$record) {
			print "WARN\n";
			print "$file\n";
			exit;
		}
		foreach my $field_035a ($record->field('035')) {
			$libris_id_035a = $field_035a->subfield('a');
			if ($libris_id_035a) {
				($libris_id) = $libris_id_035a =~ /\(LIBRIS\)(.*+)/;
				last if $libris_id;
			}
		}
		if (!$libris_id) {
			die "no libris id found";
		}
		my @libris_files = split(/\s+/, `ag -lQ '$libris_id' /opt/loadlibris/in_archive | xargs -r ls -t`);

		my $matching_record;
		MATCH: foreach my $libris_file (@libris_files) {
			my $libris_batch = MARC::Batch->new('USMARC', "$libris_file");
			#$libris_batch->strict_on();
			while (my $libris_record = $libris_batch->next()) {
				if (@{$libris_record->{_warnings}}) {
					print "Invalid\n";
					print "$libris_file\n";
					exit;
				}
				if ($libris_record->field('001')->data eq $libris_id) {
					$matching_record = $libris_record;
					last MATCH;
				}
				#else {
				#	foreach my $_035 ($libris_record->field('035')) {
				#		print "MATCHING\n";
				#		print $_035->subfield('a') . "\n"; 
				#		print $libris_id_035a . "\n"; 
				#		if ($_035->subfield('a') eq $libris_id_035a) {
				#			print "035a match for $$libris_file\n";
				#			$matching_record = $libris_record;
				#			last MATCH;
				#		}
				#	}
				#}
			}
		}
		if ($matching_record) {
			push @libris_records, $matching_record;
		}
		else {
			#Attempt partial match
			# TODO: Break out in function, 035a not matched here
			MATCH: foreach my $libris_file (@libris_files) {
				my $libris_batch = MARC::Batch->new('USMARC', "$libris_file");
				while (my $libris_record = $libris_batch->next()) {
					if ($libris_record->field('001')->data =~ /\Q$libris_id\E/) {
						$matching_record = $libris_record;
						last MATCH;
					}
				}
			}

			if ($matching_record) {
				print "Partial match found for $libris_id\n";
				my $partially_matching_dir = "$basedir/partially_matching";
				open(my $fh, '>', "$partially_matching_dir/$file.info");
				print $fh "'$libris_id' != '" . $matching_record->field('001')->data . "' ?\n";
				print $fh "Source record:\n";
				print $fh $record->as_formatted() . "\n";
				print $fh "Matched record:\n";
				print $fh $matching_record->as_formatted() . "\n";
				close($fh);

				open($fh, '>', "$partially_matching_dir/$file");
				binmode $fh, ':raw';
				$matching_record->encoding('UTF-8');
				print $fh encode('UTF-8', $matching_record->as_usmarc());
				close($fh);

				push @partially_matching_records, $matching_record;
			}
			elsif (@libris_files) {
				print "No match found for $libris_id\n";
				my $non_matching_dir = "$basedir/non_matching";
				open(my $fh, '>', "$non_matching_dir/$file.info");
				print $fh "Source record:\n";
				print $fh $record->as_formatted() . "\n";
				print $fh "Matched records:\n";
				foreach my $libris_file (@libris_files) {
					my $libris_batch = MARC::Batch->new('USMARC', "$libris_file");
					while (my $libris_record = $libris_batch->next()) {
						print $fh $libris_record->as_formatted() . "\n";
					}
				}
				close($fh);
				#push @non_matching_records, $files[0];
			}
			else {
				print "No files found for $libris_id!\n";
				copy($file, "$basedir/not_found/$file"); 
			}
		}
	}
}
open (my $fh, '>', './reimport_records.mrc');
binmode $fh, ':raw';
print $fh encode('UTF-8', join("", map { $_->as_usmarc() } @libris_records), 1);
close($fh);
