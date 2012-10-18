use PostScript::Simple;
use CircleGraph;
use Bio::AlignIO;
use Bio::SeqIO;

use constant PI 	=> 3.1415926535897932384626433832795;
use constant CENTER_X => 600; # X coordinate of circle center500
use constant CENTER_Y => 600; # Y coordinate of circle center
use constant PS_X_SIZE => 1200; # X size of the PostScript object1000
use constant PS_Y_SIZE => 1200; # Y size of the PostScript object

#
# graphics default values
#
my $MAIN_RADIUS				= 387.5;
my @colours = (	[255,0,0],		# red
				[0,255,0],		# green
				[0,0,255],		# blue
				[200,200,0],	# yellow-ish
				[255,0,255],	# magenta
				[0,255,255],	# cyan
				[255,100,0],	# orange
				[200,50,200],	# fuchsia
				[70,150,0],		# dark green
				[100,0,255]		# violet
				);

sub test_ps { # create a new PostScript object
	my $outfile = shift;
	my $p = new PostScript::Simple( colour => 1, eps => 0, units => "bp", xsize => PS_X_SIZE, ysize => PS_Y_SIZE );
	$p->newpage;

	# draw some lines and other shapes
	$p->circle(CENTER_X,CENTER_Y, $MAIN_RADIUS);
	$p->circle(CENTER_X,CENTER_Y, $MAIN_RADIUS-50);

	my @inner_coords = coords_on_circle(45,$MAIN_RADIUS-50);
	my @outer_coords = coords_on_circle(45,$MAIN_RADIUS);
	$p->line ( @inner_coords[0], @inner_coords[1], @outer_coords[0], @outer_coords[1]);

	@inner_coords = coords_on_circle(22.5,$MAIN_RADIUS-50);
	$p->line ( @inner_coords[0], @inner_coords[1], @outer_coords[0], @outer_coords[1]);

	@outer_coords = coords_on_circle(0,$MAIN_RADIUS);
	$p->line ( @inner_coords[0], @inner_coords[1], @outer_coords[0], @outer_coords[1]);

	# add some text in red
	$p->setcolour("red");
	$p->setfont("Times-Roman", 20);
	$p->text({align => 'centre'}, CENTER_X,CENTER_Y, "Hello");

	# write the output to a file
	$p->output("file.ps");
}

sub coords_on_circle {
	my $angle = shift;
	my $radius = shift;

	return ( CENTER_X + ($radius*cos(($angle * PI)/180)), CENTER_Y + ($radius*sin(($angle * PI)/180)));
}

sub draw_circle_graph_from_file_old {
	my $datafile = shift;
	my $graphfile = shift;
	my $p = new PostScript::Simple( colour => 1, eps => 0, units => "bp", xsize => PS_X_SIZE, ysize => PS_Y_SIZE );
	my $OUTER_RADIUS = 387.5;
	my $INNER_RADIUS = 337.5;

	open my $F, "<$datafile" or die "$datafile failed to open\n";
	my $line = readline $F;

	my @labels = split /\t/, $line;
	my $num_graphs = @labels-1;
	print "drawing $num_graphs graphs\n";

	# print legend
	$p->setfont("Helvetica", 12);
	if (@labels[1] =~ m/.*[:alpha:].*/) {
		for (my $i = 1; $i <= $num_graphs; $i++) {
			print ">@labels[$i]";
			$p->setcolour($colours[$i-1][0],$colours[$i-1][1],$colours[$i-1][2]);
			my $max_height = ($num_graphs * 15) + 60;
			$p->text(10,($max_height - (15*$i)), "@labels[$i]");
		}
		$line = readline $F;
	}

	my $max_diffs = 0;
	my $total_elems;
	my @positions, @differences;
	while ($line ne "") {
		my @items = split ('\t', $line);
		my $pos = shift @items;
		print scalar @items . "\n";
		$total_elems = push (@positions, $pos);
		push (@differences, @items);
		$line = readline $F;
	}

	my @sorted = sort (@differences);
	my $diff_len = @sorted;
	$max_diffs = @sorted[@sorted-1];
	my $window_size = @positions[1]-@positions[0];
	my $circle_size = @positions[$total_elems-1];

	$p->setlinewidth(2);
	for (my $j = 0; $j < $num_graphs; $j++) {
		my @coords = coords_on_circle(0,$INNER_RADIUS);
		my ($last_x, $last_y, $this_x, $this_y);
		$last_x = @coords[0];
		$last_y = @coords[1];
 		$p->setcolour($colours[$j][0],$colours[$j][1],$colours[$j][2]);
		$p->{pspages} .= "@coords[0] @coords[1] newpath moveto\n";
		for (my $i = 0; $i < $total_elems; $i++) {
			my $angle = (@positions[$i]/$circle_size) * 360;
			my $radius = $INNER_RADIUS + (($OUTER_RADIUS-$INNER_RADIUS)*(@differences[($i*$num_graphs)+$j]/$max_diffs));
			my @new_coords = coords_on_circle($angle,$radius);
			$this_x = @new_coords[0];
			$this_y = @new_coords[1];
			$p->{pspages} .= "$this_x $this_y lineto\n";
			$last_x = $this_x;
			$last_y = $this_y;
		}
		$p->{pspages} .= "@coords[0] @coords[1] lineto\nclosepath\nstroke\n";
	}

	$p->setfont("Helvetica", 6);
	$p->setcolour(black);

	for (my $i = 0; $i < $total_elems; $i++) {
		my $angle = (@positions[$i]/$circle_size) * 360;
		my $radius = $OUTER_RADIUS + 10;
		my @new_coords = coords_on_circle($angle,$radius);
		$p->text( {rotate => $angle}, @new_coords[0], @new_coords[1], "@positions[$i]");
	}

	$p->setfont("Helvetica", 12);
	$p->setcolour(black);
	$p->text(10, 10, "Maximum percent difference ($max_diffs) is scaled to 1");
	$p->text(10, 30, "Sliding window size of $window_size bp");
	$p->output($graphfile);

}

sub draw_filled_arc {
	my $radius = shift;
	my $start_angle = shift;
	my $stop_angle = shift;
	my $center_angle = ($start_angle + $stop_angle) / 2;

 	my @start_coords = coords_on_circle($start_angle, $radius);
 	my @stop_coords = coords_on_circle($stop_angle, $radius);
 	my @center_coords = coords_on_circle($center_angle, $radius);

	$p->arc({filled => 1}, CENTER_X,CENTER_Y,$radius, $start_angle, $stop_angle);
 	$p->polygon({filled => 1}, CENTER_X,CENTER_Y, @start_coords[0], @start_coords[1], @center_coords[0], @center_coords[1], @stop_coords[0], @stop_coords[1]);
}

sub set_percent_red {
	my $p = shift;
	my $percent_red = shift;
	my $scaling = ($percent_red/100);

	my @zero_red = (255,240,240);
	my @full_red = (204,0,0);
	my $r = int(((@full_red[0]-@zero_red[0])*$scaling) + @zero_red[0]);
	my $g = int(((@full_red[1]-@zero_red[1])*$scaling) + @zero_red[1]);
	my $b = int(((@full_red[2]-@zero_red[2])*$scaling) + @zero_red[2]);
	$p->setcolour($r, $g, $b);
}


# must return 1 for the file overall.
1;