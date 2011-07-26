!
!
! This command file facilitates the migration from DISPLAY statements
! to usage of the W_XXXX routines by changes the following DBL elements:
!
!	DISPLAY(	to	XCALL W_DISP(CUR_WINDOW
!	$SCR_POS(n1, n1)	to	WD_POS, n1, n2
!	$SCR_CLR(?)	to	WD_CLR, ?
!	$SCR_ATT(?)	to	WD_ATTR+ATTR_LOAD+?
!
! Of course, YOU have to put in the XCALL W_PROC statement to CREATE the CUR_WINDOW window, as a
! default, 24 line, 80 column window, and place it at line 1 column 1
!
! Usage:
!
!	$@CHGDSP file.dbl
!
!   How about *this* for a disclaimer?:
!   THE INFORMATION AND CODE PROVIDED IS PROVIDED AS IS WITHOUT WARRANTY 
!   OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO 
!   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
!   PURPOSE. IN NO EVENT SHALL SYNERGEX BE LIABLE FOR ANY DAMAGES 
!   WHATSOEVER INCLUDING DIRECT, INDIRECT, INCIDENTAL, CONSEQUENTIAL, LOSS 
!   OF BUSINESS PROFITS OR SPECIAL DAMAGES, EVEN IF SYNERGEX HAS BEEN 
!   ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
!
!   Basically, keep backups of programs that you feed to this!
!
$ set message/nofacility/noseverity/noident/notext
$ edit/tpu/noinit/nosection/nodisplay/command=SYS$INPUT 'p1'
!

procedure change_scratt

att_pos := search_quietly(scratt, forward, no_exact, main_buff);

loop
	exitif (att_pos = 0);
	position(att_pos);
	start_att := select(none);
	this_line := create_range(line_begin, line_end);

	att_bits := 0;
	fpos := search_quietly(att_code, forward, no_exact, this_line);
	loop
		exitif (fpos = 0);
		position(end_of(fpos));
		att_str := str(att_function);
		erase(select_range);
		case edit(att_str, upper)
		["CLEAR"] : att_bits := 0;
		["BOLD"] : att_bits := (att_bits or 1);
		["UNDER"] : att_bits := (att_bits or 2);
		["BLINK"] : att_bits := (att_bits or 4);
		["REVERSE"] : att_bits := (att_bits or 8);
		endcase;
		fpos := search_quietly(att_code, forward, no_exact, this_line);
	endloop;
!	Accumulate the attribute codes

	position(search(")", forward, exact, this_line));
	move_horizontal(+1);
	erase(select_range);
	start_att := 0;
!	Get rid of everything

	copy_text("WD_ATTR, ATTR_LOAD");
	if (att_bits and 1) then
		copy_text("+ATTR_BOLD");
	endif;
	if (att_bits and 2) then
		copy_text("+ATTR_UNDR");
	endif;
	if (att_bits and 4) then
		copy_text("+ATTR_BLNK");
	endif;
	if (att_bits and 8) then
		copy_text("+ATTR_RVRS");
	endif;

	att_pos := search_quietly(scratt, forward, no_exact, main_buff);
endloop;
endprocedure
		
procedure change_display

disp_pos := search_quietly(disp, forward, no_exact, main_buff);
loop
	exitif (disp_pos = 0);
	position(disp_pos);
	erase(disp_pos);
	copy_text("XCALL W_DISP(CUR_WINDOW");
	disp_pos := search_quietly(disp, forward, no_exact, main_buff);
endloop;
endprocedure
		
procedure change_scrpos

disp_pos := search_quietly(pos, forward, no_exact, main_buff);
loop
	exitif (disp_pos = 0);
	position(disp_pos);
	copy_text("WD_POS, ");
	erase(scr_pos);
	erase(close);
	erase(open);
	disp_pos := search_quietly(pos, forward, no_exact, main_buff);
endloop;
endprocedure
		
procedure change_scrclr

clear_pos := search_quietly(clr, forward, no_exact, main_buff);
loop
	exitif (clear_pos = 0);
	position(clear_pos);
	clear_str := str(clear_item);
	erase(clear_pos);
	copy_text("WD_CLR, WDC_");
	case edit(clear_str, upper)
		["SCREEN"] : copy_text("WND");
		["EOS"] : copy_text("EOW");
		["BOS"] : copy_text("BOW");
		["EOL"] : copy_text("EOL");
		["BOL"] : copy_text("BOL");
	endcase;
	clear_pos := search_quietly(clr, forward, no_exact, main_buff);
endloop;
endprocedure
		
procedure	tpu$init_procedure
endprocedure

procedure	tpu$local_init
endprocedure

whitespace := span(" 	");
! Match a section of spaces and/or tabs

open_paren := ((whitespace+"(")|"(");
close_paren := ((whitespace+")")|")");
! open and cloese with/without whitespace before.

disp := "DISPLAY" + open_paren + scan(",");
! match DISPLAY + [space] + ( chan

pos := ("$SCR_POS" @ scr_pos) + (open_paren @ open ) +
	scan(",") + "," + scan(")") + ( ")" @ close );
! match $SCR_POS + [space] ( [space] var or number , var or number )

clr := "$SCR_CLR" + (open_paren @ open) &
	(("SCREEN" | "EOS" | "BOS" | "EOL" | "BOL" ) @ clear_item ) +
	(close_paren @ close);
! match $SCR_CLR ( <clear_code> )

scratt := "$SCR_ATT" + (open_paren @ open);
! match $SCR_ATT ( 

att_code := unanchor + (("CLEAR" | "BOLD" | "UNDER" | "BLINK" |
	"REVERSE" | "GON" | "GOFF" | "SAVE" | "RESTORE") @ att_function);
! Match any $SCR_ATT() keyword

file_name := get_info(command_line, "file_name");
main_buff := create_buffer("MAIN", file_name);
position(beginning_of(main_buff));
change_display;
position(beginning_of(main_buff));
change_scrpos;
position(beginning_of(main_buff));
change_scrclr;
position(beginning_of(main_buff));
change_scratt;
exit;
$ set message/facility/severity/ident/text
$ exit