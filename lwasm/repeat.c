/*
repeat.c
Copyright © 2026 Doug Masten

This file is part of LWASM.

LWASM is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <http://www.gnu.org/licenses/>.

Contains stuff associated with REPEAT/ENDREPEAT repeat blocks and IRP blocks
*/

#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <lw_alloc.h>
#include <lw_expr.h>
#include <lw_string.h>

#include "lwasm.h"
#include "input.h"
#include "instab.h"

// from macro.c
void macro_add_to_buff(char **buff, int *loc, int *len, char c);

// from pseudo.c
char *strcond_parsearg(char **p);

// is c allowed within (not necessarily starting) an IRP parameter name?
static int irp_ident_cont(char c)
{
	return isalnum((unsigned char)c) || c == '_' || c == '.';
}

/*
Substitutes \<param> or \{<param>} in a captured IRP body line with the
current iteration's value. <param> is the name given on the IRP line itself
(see pseudo_parse_irp), not a fixed token, so nested IRP blocks that pick
different names don't collide with each other, or with MACRO's \1..\9/\{n}
argument syntax, even when an IRP is nested inside a MACRO body and its
lines get pre-scanned by the macro's own substitution before ever being
replayed. The bare \<param> form requires a non-identifier character (or
end of line) immediately after the name, so "\count" doesn't get mistaken
for a reference to a shorter parameter named "c"; the \{<param>} form exists
to disambiguate when that's not the case (e.g. immediately before more
identifier text).
*/
static void irp_expand_line(char **buff, int *bloc, int *blen, const char *line, const char *param, size_t plen, const char *val)
{
	const char *p;
	const char *v;

	for (p = line; *p; p++)
	{
		if (*p == '\\' && p[1] == '{' && strncmp(p + 2, param, plen) == 0 && p[2 + plen] == '}')
		{
			for (v = val; *v; v++)
				macro_add_to_buff(buff, bloc, blen, *v);
			p += plen + 2;
			continue;
		}
		if (*p == '\\' && strncmp(p + 1, param, plen) == 0 && !irp_ident_cont(p[1 + plen]))
		{
			for (v = val; *v; v++)
				macro_add_to_buff(buff, bloc, blen, *v);
			p += plen;
			continue;
		}
		macro_add_to_buff(buff, bloc, blen, *p);
	}
	macro_add_to_buff(buff, bloc, blen, '\n');
}

/*
REPEAT count ... ENDREPEAT   (REPT and ENDR are synonyms for REPEAT and ENDREPEAT)

Repeats the enclosed block of source lines "count" times. The block is
captured verbatim during pass 1 and then pushed back onto the input stack
count times, much like a macro expansion with no arguments. Each repetition
gets its own local symbol context. REPEAT blocks may be nested.
*/
PARSEFUNC(pseudo_parse_repeat)
{
	lw_expr_t e;
	int n;

	l -> len = 0;
	l -> hideline = 1;

	if (as -> skipcond)
	{
		skip_operand(p);
		return;
	}

	e = lwasm_parse_expr(as, p);
	if (!e)
	{
		lwasm_register_error(as, l, E_EXPRESSION_BAD);
		return;
	}
	lwasm_reduce_expr(as, e);
	if (!lw_expr_istype(e, lw_expr_type_int))
	{
		lwasm_register_error(as, l, E_EXPRESSION_NOT_CONST);
		lw_expr_destroy(e);
		return;
	}
	n = lw_expr_intval(e);
	lw_expr_destroy(e);
	if (n < 0)
	{
		lwasm_register_error(as, l, E_REPEAT_COUNT);
		return;
	}

	as -> inrepeat = 1;
	as -> repeatcount = n;
	as -> repeatlines = NULL;
	as -> repeatnumlines = 0;
}

/*
IRP param,value,value,... ... ENDR   (indefinite repeat)

Like REPEAT, but iterates once per comma separated value instead of a fixed
count. "param" gives the name used to refer to the current value within the
block, via \param or \{param} (see irp_expand_line above). The enclosed
block is captured verbatim during pass 1 exactly as for REPEAT; substitution
happens only once the block is replayed, before each replayed copy is
re-parsed. Values (and the parameter name) may be quoted with '"' or "'" to
include whitespace or commas. IRP blocks may be nested, and may nest with
REPEAT and vice versa (including inside a MACRO body) -- as long as nested
IRPs don't reuse the same parameter name, since substitution is a single
textual pass over the whole captured block, including any not-yet-executed
nested block.
*/
PARSEFUNC(pseudo_parse_irp)
{
	char *arg;
	char *c;

	l -> len = 0;
	l -> hideline = 1;

	if (as -> skipcond)
	{
		skip_operand(p);
		return;
	}

	while (isspace((unsigned char)**p))
		(*p)++;

	arg = strcond_parsearg(p);
	if (!(isalpha((unsigned char)arg[0]) || arg[0] == '_' || arg[0] == '.'))
	{
		lwasm_register_error(as, l, E_IRP_BADPARAM);
		lw_free(arg);
		skip_operand(p);
		return;
	}
	for (c = arg + 1; *c; c++)
	{
		if (!irp_ident_cont(*c))
		{
			lwasm_register_error(as, l, E_IRP_BADPARAM);
			lw_free(arg);
			skip_operand(p);
			return;
		}
	}

	as -> irpparam = arg;
	as -> irpargs = NULL;
	as -> irpnumargs = 0;

	for (;;)
	{
		while (isspace((unsigned char)**p))
			(*p)++;
		if (!**p)
			break;
		arg = strcond_parsearg(p);
		as -> irpargs = lw_realloc(as -> irpargs, sizeof(char *) * (as -> irpnumargs + 1));
		as -> irpargs[as -> irpnumargs++] = arg;
	}

	if (as -> irpnumargs == 0)
	{
		lwasm_register_error(as, l, E_IRP_NOARGS);
		lw_free(as -> irpparam);
		as -> irpparam = NULL;
		return;
	}

	as -> inrepeat = 1;
	as -> inirp = 1;
	as -> repeatcount = as -> irpnumargs;
	as -> repeatlines = NULL;
	as -> repeatnumlines = 0;
}

PARSEFUNC(pseudo_parse_endrepeat)
{
	int i, n;
	int oldcontext;
	int bloc = 0, blen = 0;
	size_t irpplen;
	char *linebuff = NULL;
	char ctcbuf[100];
	char *t;

	l -> len = 0;
	l -> hideline = 1;
	skip_operand(p);

	if (as -> skipcond)
		return;

	if (!as -> inrepeat)
	{
		lwasm_register_error(as, l, E_REPEAT_ENDREPEAT);
		return;
	}
	as -> inrepeat = 0;

	oldcontext = as -> context;
	irpplen = as -> inirp ? strlen(as -> irpparam) : 0;
	for (n = 0; n < as -> repeatcount; n++)
	{
		// each repetition is its own context for local symbols
		snprintf(ctcbuf, sizeof(ctcbuf), "\001\001SETCONTEXT %d\n", lwasm_next_context(as));
		for (t = ctcbuf; *t; t++)
			macro_add_to_buff(&linebuff, &bloc, &blen, *t);
		for (i = 0; i < as -> repeatnumlines; i++)
		{
			if (as -> inirp)
			{
				irp_expand_line(&linebuff, &bloc, &blen, as -> repeatlines[i], as -> irpparam, irpplen, as -> irpargs[n]);
			}
			else
			{
				for (t = as -> repeatlines[i]; *t; t++)
					macro_add_to_buff(&linebuff, &bloc, &blen, *t);
				macro_add_to_buff(&linebuff, &bloc, &blen, '\n');
			}
		}
	}

	if (as -> inirp)
	{
		for (n = 0; n < as -> irpnumargs; n++)
			lw_free(as -> irpargs[n]);
		lw_free(as -> irpargs);
		as -> irpargs = NULL;
		as -> irpnumargs = 0;
		lw_free(as -> irpparam);
		as -> irpparam = NULL;
		as -> inirp = 0;
	}

	// restore context after the last repetition, back in the outer scope
	snprintf(ctcbuf, sizeof(ctcbuf), "\001\001SETCONTEXT %d\n", oldcontext);
	for (t = ctcbuf; *t; t++)
		macro_add_to_buff(&linebuff, &bloc, &blen, *t);

	// a label on the ENDR line refers to the address just past the
	// repeated block; emit it as its own line so it gets assembled for
	// real, in the outer scope, after all repetitions have been replayed
	if (l -> sym)
	{
		for (t = l -> sym; *t; t++)
			macro_add_to_buff(&linebuff, &bloc, &blen, *t);
		macro_add_to_buff(&linebuff, &bloc, &blen, '\n');
	}

	// restore line numbering
	snprintf(ctcbuf, sizeof(ctcbuf), "\001\001SETLINENO %d\n", l -> lineno + 1);
	for (t = ctcbuf; *t; t++)
		macro_add_to_buff(&linebuff, &bloc, &blen, *t);
	macro_add_to_buff(&linebuff, &bloc, &blen, 0);

	input_openstring(as, "REPEAT", linebuff);
	lw_free(linebuff);

	for (i = 0; i < as -> repeatnumlines; i++)
		lw_free(as -> repeatlines[i]);
	lw_free(as -> repeatlines);
	as -> repeatlines = NULL;
	as -> repeatnumlines = 0;
}

int add_repeat_line(asmstate_t *as, char *optr)
{
	if (!as -> inrepeat)
		return 0;

	as -> repeatlines = lw_realloc(as -> repeatlines, sizeof(char *) * (as -> repeatnumlines + 1));
	as -> repeatlines[as -> repeatnumlines++] = lw_strdup(optr);
	return 1;
}
