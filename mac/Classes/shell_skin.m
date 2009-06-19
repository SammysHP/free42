/*****************************************************************************
 * Free42 -- an HP-42S calculator simulator
 * Copyright (C) 2004-2009  Thomas Okken
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, version 2,
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see http://www.gnu.org/licenses/.
 *****************************************************************************/

#import "shell_skin.h"

static FILE *external_file;
static long builtin_length;
static long builtin_pos;
static const unsigned char *builtin_file;

static int skin_type;
static int skin_width, skin_height;
static int skin_ncolors;
static const SkinColor *skin_colors = NULL;
static int skin_y;
static CGImageRef skin_image = NULL;
static unsigned char *skin_bitmap = NULL;
static int skin_bytesperline;

int skin_init_image(int type, int ncolors, const SkinColor *colors,
					int width, int height) {
	if (skin_image != NULL) {
		CGImageRelease(skin_image);
		skin_image = NULL;
		skin_bitmap = NULL;
	}
	
	skin_type = type;
	skin_ncolors = ncolors;
	skin_colors = colors;
	
	switch (type) {
		case IMGTYPE_MONO:
			skin_bytesperline = (width + 7) >> 3;
			break;
		case IMGTYPE_GRAY:
			skin_bytesperline = width;
			break;
		case IMGTYPE_TRUECOLOR:
		case IMGTYPE_COLORMAPPED:
			skin_bytesperline = width * 3;
			break;
		default:
			return 0;
	}
	
	skin_bitmap = (unsigned char *) malloc(skin_bytesperline * height);
	// TODO - handle memory allocation failure
	skin_width = width;
	skin_height = height;
	skin_y = skin_height;
	return skin_bitmap != NULL;
}

void skin_put_pixels(unsigned const char *data) {
	skin_y--;
	unsigned char *dst = skin_bitmap + skin_y * skin_bytesperline;
	if (skin_type == IMGTYPE_COLORMAPPED) {
		int src_bytesperline = skin_bytesperline / 3;
		for (int i = 0; i < src_bytesperline; i++) {
			int index = data[i] & 255;
			const SkinColor *c = skin_colors + index;
			*dst++ = c->r;
			*dst++ = c->g;
			*dst++ = c->b;
		}
	} else
		memcpy(dst, data, skin_bytesperline);
}

static void MyProviderReleaseData(void *info,  const void *data, size_t size) {
	free((void *) data);
}

void skin_finish_image() {
	int bits_per_component;
	int bits_per_pixel;
	CGColorSpaceRef color_space;
	
	switch (skin_type) {
		case IMGTYPE_MONO:
			bits_per_component = 1;
			bits_per_pixel = 1;
			color_space = CGColorSpaceCreateDeviceGray();
			break;
		case IMGTYPE_GRAY:
			bits_per_component = 8;
			bits_per_pixel = 8;
			color_space = CGColorSpaceCreateDeviceGray();
			break;
		case IMGTYPE_COLORMAPPED:
		case IMGTYPE_TRUECOLOR:
			bits_per_component = 8;
			bits_per_pixel = 24;
			color_space = CGColorSpaceCreateDeviceRGB();
			break;
	}
	
	int bytes_per_line = (skin_width * bits_per_pixel + 7) >> 3;
	
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, skin_bitmap, bytes_per_line * skin_height, MyProviderReleaseData);
	skin_image = CGImageCreate(skin_width, skin_height, bits_per_component, bits_per_pixel, bytes_per_line,
							   color_space, kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(color_space);
	skin_bitmap = NULL;
}

int skin_getchar() {
	if (external_file != NULL)
		return fgetc(external_file);
	else if (builtin_pos < builtin_length)
		return builtin_file[builtin_pos++];
	else
		return EOF;
}

#if 0
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <dirent.h>

#include <Xm/Xm.h>
#include <Xm/Separator.h>
#include <Xm/ToggleB.h>

#include "shell_skin.h"
#include "shell_loadimage.h"
#include "shell_main.h"
#include "core_main.h"


/**************************/
/* Skin description stuff */
/**************************/

typedef struct {
    int x, y;
} SkinPoint;

typedef struct {
    int x, y, width, height;
} SkinRect;

typedef struct {
    int code, shifted_code;
    SkinRect sens_rect;
    SkinRect disp_rect;
    SkinPoint src;
} SkinKey;

#define SKIN_MAX_MACRO_LENGTH 31

typedef struct _SkinMacro {
    int code;
    unsigned char macro[SKIN_MAX_MACRO_LENGTH + 1];
    struct _SkinMacro *next;
} SkinMacro;

typedef struct {
    SkinRect disp_rect;
    SkinPoint src;
} SkinAnnunciator;

static SkinRect skin;
static SkinPoint display_loc;
static SkinPoint display_scale;
static XColor display_bg, display_fg;
static SkinKey *keylist = NULL;
static int nkeys = 0;
static int keys_cap = 0;
static SkinMacro *macrolist = NULL;
static SkinAnnunciator annunciators[7];

static FILE *external_file;
static long builtin_length;
static long builtin_pos;
static const unsigned char *builtin_file;

static XImage *skin_image = NULL;
static int skin_ncolors = 0;
static XColor skin_color[256];
static int skin_y;
static int skin_type;
static const SkinColor *skin_cmap;

static XImage *disp_image = NULL;
static int disp_bg_allocated = 0;
static int disp_fg_allocated = 0;
static GC disp_gc = None;
static GC disp_inv_gc = None;
static int grayramp_size = 0;
static int colorcube_size = 0;
static int exact_colors;
static unsigned int rmax, rmult, bmax, bmult, gmax, gmult;

static int *dr, *dg, *db, *nextdr, *nextdg, *nextdb;

static keymap_entry *keymap = NULL;
static int keymap_length;

static bool display_enabled = true;


/**********************************************************/
/* Linked-in skins; defined in the skins.c, which in turn */
/* is generated by skin2c.c under control of skin2c.conf  */
/**********************************************************/

extern const int skin_count;
extern const char *skin_name[];
extern const long skin_layout_size[];
extern const unsigned char *skin_layout_data[];
extern const long skin_bitmap_size[];
extern const unsigned char *skin_bitmap_data[];


/*******************/
/* Local functions */
/*******************/

static void addMenuItem(Widget w, const char *name);
static void selectSkinCB(Widget w, XtPointer ud, XtPointer cd);
static int skin_open(const char *name, int open_layout);
static int skin_gets(char *buf, int buflen);
static void skin_close();
static int get_real_depth();
static int allocate_exact(int ncolors, const SkinColor *colors);
static int allocate_colorcube();
static void allocate_grayramp();
static void calc_rgb_masks();


static void addMenuItem(Widget w, const char *name) {
    XmString s;
    Arg args[2];
    int nargs = 0;
    Widget button;
    
    if (state.skinName[0] == 0) {
	strcpy(state.skinName, name);
	XtSetArg(args[nargs], XmNset, XmSET); nargs++;
    } else if (strcmp(state.skinName, name) == 0) {
	XtSetArg(args[nargs], XmNset, XmSET); nargs++;
    }
    
    s = XmStringCreateLocalized((char *) name);
    XtSetArg(args[nargs], XmNlabelString, s); nargs++;
    button = XtCreateManagedWidget(name,
				   xmToggleButtonWidgetClass,
				   w,
				   args, nargs);
    XmStringFree(s);
    XtAddCallback(button, XmNvalueChangedCallback, selectSkinCB, NULL);
}

static void selectSkinCB(Widget w, XtPointer ud, XtPointer cd) {
    XmString label;
    XmStringContext context;
    char *seg;
    XmStringCharSet tag;
    XmStringDirection dir;
    Boolean separator;

    XmToggleButtonCallbackStruct *cbs = (XmToggleButtonCallbackStruct *) cd;
    if (cbs->set != XmSET)
	return;

    XtVaGetValues(w, XmNlabelString, &label, NULL);
    XmStringInitContext(&context, label);
    XmStringGetNextSegment(context, &seg, &tag, &dir, &separator);
    if (strcmp(state.skinName, seg) != 0) {
	int w, h;
	strcpy(state.skinName, seg);
	skin_load(&w, &h);
	core_repaint_display();
	allow_mainwindow_resize();
	XtVaSetValues(calc_widget, XmNwidth, w, XmNheight, h, NULL);
	disallow_mainwindow_resize();
	XClearWindow(display, calc_canvas);
    }
    XtFree(seg);
    XtFree(tag);
    XmStringFreeContext(context);
    XmStringFree(label);
}

static int skin_open(const char *name, int open_layout) {
    int i;
    char namebuf[1024];

    /* Look for built-in skin first */
    for (i = 0; i < skin_count; i++) {
	if (strcmp(name, skin_name[i]) == 0) {
	    external_file = NULL;
	    builtin_pos = 0;
	    if (open_layout) {
		builtin_length = skin_layout_size[i];
		builtin_file = skin_layout_data[i];
	    } else {
		builtin_length = skin_bitmap_size[i];
		builtin_file = skin_bitmap_data[i];
	    }
	    return 1;
	}
    }

    /* name did not match a built-in skin; look for file */
    snprintf(namebuf, 1024, "%s/%s.%s", free42dirname, name,
					open_layout ? "layout" : "gif");
    external_file = fopen(namebuf, "r");
    return external_file != NULL;
}

int skin_getchar() {
    if (external_file != NULL)
	return fgetc(external_file);
    else if (builtin_pos < builtin_length)
	return builtin_file[builtin_pos++];
    else
	return EOF;
}

static int skin_gets(char *buf, int buflen) {
    int p = 0;
    int eof = -1;
    int comment = 0;
    while (p < buflen - 1) {
	int c = skin_getchar();
	if (eof == -1)
	    eof = c == EOF;
	if (c == EOF || c == '\n' || c == '\r')
	    break;
	/* Remove comments */
	if (c == '#')
	    comment = 1;
	if (comment)
	    continue;
	/* Suppress leading spaces */
	if (p == 0 && isspace(c))
	    continue;
	buf[p++] = c;
    }
    buf[p++] = 0;
    return p > 1 || !eof;
}

void skin_rewind() {
    if (external_file != NULL)
	rewind(external_file);
    else
	builtin_pos = 0;
}

static void skin_close() {
    if (external_file != NULL)
	fclose(external_file);
}

static int get_real_depth() {
    static int d = 0;
    if (d != 0)
	return d;

    d = depth;
    if (d > visual->bits_per_rgb)
	d = visual->bits_per_rgb;
    if (d > 8)
	d = 8;

    if (visual->c_class == TrueColor || visual->c_class == DirectColor) {
	unsigned long redmask = visual->red_mask;
	unsigned long greenmask = visual->green_mask;
	unsigned long bluemask = visual->blue_mask;
	int redbits = 0, greenbits = 0, bluebits = 0;
	while (redmask != 0 || greenmask != 0 || bluemask != 0) {
	    redbits += redmask & 1;
	    redmask >>= 1;
	    greenbits += greenmask & 1;
	    greenmask >>= 1;
	    bluebits += bluemask & 1;
	    bluemask >>= 1;
	}
	if (d > redbits)
	    d = redbits;
	if (d > greenbits)
	    d = greenbits;
	if (d > bluebits)
	    d = bluebits;
    }

    return d;
}

static int allocate_exact(int ncolors, const SkinColor *colors) {
    int n;
    for (n = 0; n < ncolors; n++) {
	skin_color[n].red = colors[n].r * 257;
	skin_color[n].green = colors[n].g * 257;
	skin_color[n].blue = colors[n].b * 257;
	skin_color[n].flags = DoRed | DoGreen | DoBlue;
	if (!XAllocColor(display, colormap, &skin_color[n])) {
	    unsigned long pixels[256];
	    int i;
	    for (i = 0; i < n; i++)
		pixels[i] = skin_color[i].pixel;
	    XFreeColors(display, colormap, pixels, n, 0);
	    return 0;
	}
    }
    skin_ncolors = ncolors;
    return 1;
}

static int allocate_colorcube() {
    int done = 0;
    colorcube_size = 1;
    while (colorcube_size * colorcube_size * colorcube_size <= (1 << depth))
	colorcube_size++;
    colorcube_size--;
    while (!done && colorcube_size > 1) {
	int n = 0;
	int r, g, b;
	done = 1;
	for (r = 0; r < colorcube_size; r++)
	    for (g = 0; g < colorcube_size; g++)
		for (b = 0; b < colorcube_size; b++) {
		    int success;
		    skin_color[n].red = r * 65535 / (colorcube_size - 1);
		    skin_color[n].green = g * 65535 / (colorcube_size - 1);
		    skin_color[n].blue = b * 65535 / (colorcube_size - 1);
		    success = XAllocColor(display, colormap, &skin_color[n]);
		    if (!success) {
			if (n > 0) {
			    unsigned long pixels[256];
			    int i;
			    for (i = 0; i < n; i++)
				pixels[i] = skin_color[i].pixel;
			    XFreeColors(display, colormap, pixels, n, 0);
			    done = 0;
			}
			goto endloop;
		    }
		    n++;
		}
	endloop:
	if (!done)
	    colorcube_size--;
    }

    if (done)
	skin_ncolors = colorcube_size * colorcube_size * colorcube_size;
    else
	colorcube_size = 0;
    return done;
}

static void allocate_grayramp() {
    int done = 0;
    grayramp_size = 1 << get_real_depth();
    while (!done) {
	int n;
	done = 1;
	if (grayramp_size == 2) {
	    skin_color[0].pixel = black;
	    skin_color[0].red = skin_color[0].green = skin_color[0].blue = 0;
	    skin_color[1].pixel = white;
	    skin_color[1].red = skin_color[1].green = skin_color[1].blue = 65535;
	    break;
	}
	for (n = 0; n < grayramp_size; n++) {
	    int success;
	    skin_color[n].red = skin_color[n].green = skin_color[n].blue
		= n * 65535 / (grayramp_size - 1);
	    success = XAllocColor(display, colormap, &skin_color[n]);
	    if (!success) {
		if (n > 0) {
		    unsigned long pixels[256];
		    int i;
		    for (i = 0; i < n; i++)
			pixels[i] = skin_color[i].pixel;
		    XFreeColors(display, colormap, pixels, n, 0);
		    done = 0;
		}
		break;
	    }
	}
	if (!done)
	    grayramp_size >>= 1;
    }
}

static void calc_rgb_masks() {
    static int inited = 0;
    if (inited)
	return;
    if (visual->c_class != TrueColor && visual->c_class != DirectColor) {
	inited = 1;
	return;
    }
    rmax = visual->red_mask;
    rmult = 0;
    while ((rmax & 1) == 0) {
	rmax >>= 1;
	rmult++;
    }
    gmax = visual->green_mask; 
    gmult = 0;
    while ((gmax & 1) == 0) {
	gmax >>= 1;
	gmult++;
    }
    bmax = visual->blue_mask;
    bmult = 0;
    while ((bmax & 1) == 0) {
	bmax >>= 1;
	bmult++;
    }
    inited = 1; 
}

static int case_insens_comparator(const void *a, const void *b) {
    return strcasecmp(*(const char **) a, *(const char **) b);
}

void skin_menu_update(Widget w, XtPointer ud, XtPointer cd) {
    Widget *children;
    Cardinal numChildren;
    DIR *dir;
    struct dirent *dent;
    char *skinname[100];
    int nskins = 0, i;
    int have_separator = 0;

    XtVaGetValues(w, XmNchildren, &children,
		     XmNnumChildren, &numChildren,
		     NULL);

    while (numChildren > 0) {
	XtDestroyWidget(children[--numChildren]);
	XtVaGetValues(w, XmNchildren, &children, NULL);
    }

    for (i = 0; i < skin_count; i++)
	addMenuItem(w, skin_name[i]);

    dir = opendir(free42dirname);
    if (dir == NULL)
	return;

    while ((dent = readdir(dir)) != NULL && nskins < 100) {
	int namelen = strlen(dent->d_name);
	char *skn;
	if (namelen < 7)
	    continue;
	if (strcmp(dent->d_name + namelen - 7, ".layout") != 0)
	    continue;
	skn = (char *) malloc(namelen - 6);
	// TODO - handle memory allocation failure
	memcpy(skn, dent->d_name, namelen - 7);
	skn[namelen - 7] = 0;
	skinname[nskins++] = skn;
    }
    closedir(dir);

    qsort(skinname, nskins, sizeof(char *), case_insens_comparator);
    for (i = 0; i < nskins; i++) {
	int j;
	for (j = 0; j < skin_count; j++)
	    if (strcmp(skinname[i], skin_name[j]) == 0)
		goto skip;
	if (!have_separator) {
	    XtCreateManagedWidget("Separator",
				  xmSeparatorWidgetClass,
				  w,
				  NULL, 0);
	    have_separator = 1;
	}
	addMenuItem(w, skinname[i]);
	skip:
	free(skinname[i]);
    }
}

void skin_load(int *width, int *height) {
    char line[1024];
    int success;
    int size;
    XGCValues values;
    int kmcap;
    int lineno = 0;

    if (state.skinName[0] == 0) {
	fallback_on_1st_builtin_skin:
	strcpy(state.skinName, skin_name[0]);
    }

    /*************************/
    /* Load skin description */
    /*************************/

    if (!skin_open(state.skinName, 1))
	goto fallback_on_1st_builtin_skin;

    if (keylist != NULL)
	free(keylist);
    keylist = NULL;
    nkeys = 0;
    keys_cap = 0;

    while (macrolist != NULL) {
	SkinMacro *m = macrolist->next;
	free(macrolist);
	macrolist = m;
    }

    if (keymap != NULL)
	free(keymap);
    keymap = NULL;
    keymap_length = 0;
    kmcap = 0;

    while (skin_gets(line, 1024)) {
	lineno++;
	if (*line == 0)
	    continue;
	if (strncasecmp(line, "skin:", 5) == 0) {
	    int x, y, width, height;
	    if (sscanf(line + 5, " %d,%d,%d,%d", &x, &y, &width, &height) == 4){
		skin.x = x;
		skin.y = y;
		skin.width = width;
		skin.height = height;
	    }
	} else if (strncasecmp(line, "display:", 8) == 0) {
	    int x, y, xscale, yscale;
	    unsigned long bg, fg;
	    if (sscanf(line + 8, " %d,%d %d %d %lx %lx", &x, &y,
					    &xscale, &yscale, &bg, &fg) == 6) {
		display_loc.x = x;
		display_loc.y = y;
		display_scale.x = xscale;
		display_scale.y = yscale;
		display_bg.red = (bg >> 16) * 257;
		display_bg.green = ((bg >> 8) & 255) * 257;
		display_bg.blue = (bg & 255) * 257;
		display_bg.flags = DoRed | DoGreen | DoBlue;
		display_fg.red = (fg >> 16) * 257;
		display_fg.green = ((fg >> 8) & 255) * 257;
		display_fg.blue = (fg & 255) * 257;
		display_fg.flags = DoRed | DoGreen | DoBlue;
	    }
	} else if (strncasecmp(line, "key:", 4) == 0) {
	    char keynumbuf[20];
	    int keynum, shifted_keynum;
	    int sens_x, sens_y, sens_width, sens_height;
	    int disp_x, disp_y, disp_width, disp_height;
	    int act_x, act_y;
	    if (sscanf(line + 4, " %s %d,%d,%d,%d %d,%d,%d,%d %d,%d",
				 keynumbuf,
				 &sens_x, &sens_y, &sens_width, &sens_height,
				 &disp_x, &disp_y, &disp_width, &disp_height,
				 &act_x, &act_y) == 11) {
		int n = sscanf(keynumbuf, "%d,%d", &keynum, &shifted_keynum);
		if (n > 0) {
		    if (n == 1)
			shifted_keynum = keynum;
		    SkinKey *key;
		    if (nkeys == keys_cap) {
			keys_cap += 50;
			keylist = (SkinKey *)
				realloc(keylist, keys_cap * sizeof(SkinKey));
			// TODO - handle memory allocation failure
		    }
		    key = keylist + nkeys;
		    key->code = keynum;
		    key->shifted_code = shifted_keynum;
		    key->sens_rect.x = sens_x;
		    key->sens_rect.y = sens_y;
		    key->sens_rect.width = sens_width;
		    key->sens_rect.height = sens_height;
		    key->disp_rect.x = disp_x;
		    key->disp_rect.y = disp_y;
		    key->disp_rect.width = disp_width;
		    key->disp_rect.height = disp_height;
		    key->src.x = act_x;
		    key->src.y = act_y;
		    nkeys++;
		}
	    }
	} else if (strncasecmp(line, "macro:", 6) == 0) {
	    char *tok = strtok(line + 6, " ");
	    int len = 0;
	    SkinMacro *macro = NULL;
	    while (tok != NULL) {
		char *endptr;
		long n = strtol(tok, &endptr, 10);
		if (*endptr != 0) {
		    /* Not a proper number; ignore this macro */
		    if (macro != NULL) {
			free(macro);
			macro = NULL;
			break;
		    }
		}
		if (macro == NULL) {
		    if (n < 38 || n > 255)
			/* Macro code out of range; ignore this macro */
			break;
		    macro = (SkinMacro *) malloc(sizeof(SkinMacro));
		    // TODO - handle memory allocation failure
		    macro->code = n;
		} else if (len < SKIN_MAX_MACRO_LENGTH) {
		    if (n < 1 || n > 37) {
			/* Key code out of range; ignore this macro */
			free(macro);
			macro = NULL;
			break;
		    }
		    macro->macro[len++] = n;
		}
		tok = strtok(NULL, " ");
	    }
	    if (macro != NULL) {
		macro->macro[len++] = 0;
		macro->next = macrolist;
		macrolist = macro;
	    }
	} else if (strncasecmp(line, "annunciator:", 12) == 0) {
	    int annnum;
	    int disp_x, disp_y, disp_width, disp_height;
	    int act_x, act_y;
	    if (sscanf(line + 12, " %d %d,%d,%d,%d %d,%d",
				  &annnum,
				  &disp_x, &disp_y, &disp_width, &disp_height,
				  &act_x, &act_y) == 7) {
		if (annnum >= 1 && annnum <= 7) {
		    SkinAnnunciator *ann = annunciators + (annnum - 1);
		    ann->disp_rect.x = disp_x;
		    ann->disp_rect.y = disp_y;
		    ann->disp_rect.width = disp_width;
		    ann->disp_rect.height = disp_height;
		    ann->src.x = act_x;
		    ann->src.y = act_y;
		}
	    }
	} else if (strchr(line, ':') != NULL) {
	    keymap_entry *entry = parse_keymap_entry(line, lineno);
	    if (entry != NULL) {
		if (keymap_length == kmcap) {
		    kmcap += 50;
		    keymap = (keymap_entry *)
				realloc(keymap, kmcap * sizeof(keymap_entry));
		    // TODO - handle memory allocation failure
		}
		memcpy(keymap + (keymap_length++), entry, sizeof(keymap_entry));
	    }
	}
    }

    skin_close();

    /********************/
    /* Load skin bitmap */
    /********************/

    if (!skin_open(state.skinName, 0))
	goto fallback_on_1st_builtin_skin;

    /* shell_loadimage() calls skin_getchar() and skin_rewind() to load the
     * image from the compiled-in or on-disk file; it calls skin_init_image(),
     * skin_put_pixels(), and skin_finish_image() to create the in-memory
     * representation.
     */
    success = shell_loadimage();
    skin_close();

    if (!success)
	goto fallback_on_1st_builtin_skin;

    *width = skin.width;
    *height = skin.height;

    /********************************/
    /* (Re)build the display bitmap */
    /********************************/

    if (disp_image != NULL) {
	free(disp_image->data);
	XFree(disp_image);
    }

    disp_image = XCreateImage(display, visual, 1, XYBitmap, 0, NULL,
			      131 * display_scale.x, 16 * display_scale.y,
			      8, 0);
    size = disp_image->bytes_per_line * disp_image->height;
    disp_image->data = (char *) malloc(size);
    // TODO - handle memory allocation failure
    memset(disp_image->data, 255, size);

    /*************************************/
    /* (Re)allocate display fg/bg colors */
    /*************************************/
    
    if (disp_bg_allocated)
	XFreeColors(display, colormap, &display_bg.pixel, 1, 0);
    if (disp_fg_allocated)
	XFreeColors(display, colormap, &display_fg.pixel, 1, 0);
    disp_bg_allocated = XAllocColor(display, colormap, &display_bg);
    if (disp_bg_allocated) {
	disp_fg_allocated = XAllocColor(display, colormap, &display_fg);
	if (!disp_fg_allocated) {
	    XFreeColors(display, colormap, &display_bg.pixel, 1, 0);
	    disp_bg_allocated = 0;
	}
    }
    if (!disp_bg_allocated) {
	display_bg.pixel = white;
	display_fg.pixel = black;
    }

    values.foreground = display_fg.pixel;
    values.background = display_bg.pixel;
    if (disp_gc == None)
	disp_gc = XCreateGC(display, rootwindow,
			    GCForeground | GCBackground, &values);
    else
	XChangeGC(display, disp_gc, GCForeground | GCBackground, &values);
    values.foreground = display_bg.pixel;
    values.background = display_fg.pixel;
    if (disp_inv_gc == None)
	disp_inv_gc = XCreateGC(display, rootwindow,
			    GCForeground | GCBackground, &values);
    else
	XChangeGC(display, disp_inv_gc, GCForeground | GCBackground, &values);
}

int skin_init_image(int type, int ncolors, const SkinColor *colors,
		    int width, int height) {
    calc_rgb_masks();

    if (skin_image != NULL) {
	free(skin_image->data);
	XFree(skin_image);
	skin_image = NULL;
    }

    if (skin_ncolors > 0 && grayramp_size != 2) {
	unsigned long pixels[256];
	int i;
	for (i = 0; i < skin_ncolors; i++)
	    pixels[i] = skin_color[i].pixel;
	XFreeColors(display, colormap, pixels, skin_ncolors, 0);
    }
    skin_ncolors = 0;
    grayramp_size = 0;
    colorcube_size = 0;
    exact_colors = 0;
    
    skin_y = 0;
    skin_type = type;
    
    if (type == IMGTYPE_MONO) {
	skin_image = XCreateImage(display, visual, 1, XYBitmap,
				  0, NULL, width, height, 32, 0);
	skin_image->data = (char *) malloc(skin_image->bytes_per_line * height);
	// TODO - handle memory allocation failure
	dr = dg = db = nextdr = nextdg = nextdb = NULL;
	return 1;
    } else if (type == IMGTYPE_GRAY) {
	int i;
	allocate_grayramp();
	skin_image = XCreateImage(display, visual, depth, ZPixmap,
				  0, NULL, width, height, 32, 0);
	skin_image->data = (char *) malloc(skin_image->bytes_per_line * height);
	dg = (int *) malloc(skin_image->width * sizeof(int));
	nextdg = (int *) malloc(skin_image->width * sizeof(int));
	// TODO - handle memory allocation failure
	dr = db = nextdr = nextdb = NULL;
	for (i = 0; i < skin_image->width; i++)
	    dg[i] = nextdg[i] = 0;
	return 1;
    } else if (type == IMGTYPE_COLORMAPPED) {
	int i;
	if (visual->c_class == PseudoColor) {
	    if (allocate_exact(ncolors, colors)) {
		exact_colors = 1;
		dr = dg = db = nextdr = nextdg = nextdb = NULL;
		goto cmap_colors_done;
	    }
	}
	dr = (int *) malloc(width * sizeof(int));
	dg = (int *) malloc(width * sizeof(int));
	db = (int *) malloc(width * sizeof(int));
	nextdr = (int *) malloc(width * sizeof(int));
	nextdg = (int *) malloc(width * sizeof(int));
	nextdb = (int *) malloc(width * sizeof(int));
	// TODO - handle memory allocation failure
	for (i = 0; i < width; i++)
	    dr[i] = dg[i] = db[i] = nextdr[i] = nextdg[i] = nextdb[i] = 0;
	skin_cmap = colors;
	if (visual->c_class == PseudoColor || visual->c_class == StaticColor) {
	    if (allocate_colorcube())
		goto cmap_colors_done;
	}
	if (visual->c_class != TrueColor && visual->c_class != DirectColor)
	    allocate_grayramp();
	cmap_colors_done:
	skin_image = XCreateImage(display, visual, depth, ZPixmap,
				  0, NULL, width, height, 32, 0);
	skin_image->data = (char *) malloc(skin_image->bytes_per_line * height);
	// TODO - handle memory allocation failure
	return 1;
    } else if (type == IMGTYPE_TRUECOLOR) {
	int i;
	if (visual->c_class == PseudoColor || visual->c_class == StaticColor) {
	    if (allocate_colorcube())
		goto true_colors_done;
	}
	if (visual->c_class != TrueColor && visual->c_class != DirectColor)
	    allocate_grayramp();
	true_colors_done:
	skin_image = XCreateImage(display, visual, depth, ZPixmap,
				  0, NULL, width, height, 32, 0);
	skin_image->data = (char *) malloc(skin_image->bytes_per_line * height);
	dr = (int *) malloc(width * sizeof(int));
	dg = (int *) malloc(width * sizeof(int));
	db = (int *) malloc(width * sizeof(int));
	nextdr = (int *) malloc(width * sizeof(int));
	nextdg = (int *) malloc(width * sizeof(int));
	nextdb = (int *) malloc(width * sizeof(int));
	// TODO - handle memory allocation failure
	for (i = 0; i < width; i++)
	    dr[i] = dg[i] = db[i] = nextdr[i] = nextdg[i] = nextdb[i] = 0;
	return 1;
    } else
	return 0;
}

void skin_put_pixels(unsigned const char *data) {
    int x, start, end, dir, *temp;
    int prevx, nextx;
    unsigned long pixel;

    if (skin_type == IMGTYPE_MONO) {
	for (x = 0; x < skin_image->width; x++) {
	    pixel = (data[x >> 3] & (1 << (x & 7))) == 0;
	    XPutPixel(skin_image, x, skin_y, pixel);
	}
    } else if (grayramp_size != 0) {
	/* type == IMGTYPE_GRAY, or IMGTYPE_COLORMAPPED/TRUECOLOR but
	 * no colors available on the screen */
	int g, dG = 0;
	dir = ((skin_y & 1) << 1) - 1;
	if (dir == 1) {
	    start = 0;
	    end = skin_image->width;
	} else {
	    start = skin_image->width - 1;
	    end = -1;
	}
	temp = nextdg; nextdg = dg; dg = temp;
	for (x = start; x != end; x += dir) {
	    int graylevel;
	    if (skin_type == IMGTYPE_GRAY)
		g = data[x];
	    else {
		int red, green, blue;
		if (skin_type == IMGTYPE_COLORMAPPED) {
		    unsigned char p = data[x];
		    red = skin_cmap[p].r;
		    green = skin_cmap[p].g;
		    blue = skin_cmap[p].b;
		} else {
		    int xx = (x << 2) + 1;
		    red = data[xx++];
		    green = data[xx++];
		    blue = data[xx++];
		}
		g = (red * 306 + green * 601 + blue * 117) / 1024;
	    }
	    g += (dg[x] + dG) >> 4;
	    if (g < 0) g = 0; else if (g > 255) g = 255;
	    dg[x] = 0;
	    graylevel = (g * (grayramp_size - 1) + 127) / 255;
	    if (graylevel >= grayramp_size)
		graylevel = grayramp_size - 1;
	    dG = g - (skin_color[graylevel].red >> 8);
	    pixel = skin_color[graylevel].pixel;
	    XPutPixel(skin_image, x, skin_y, pixel);
	    prevx = x - dir;
	    nextx = x + dir;
	    if (prevx >= 0 && prevx < skin_image->width)
		nextdg[prevx] += dG * 3;
	    nextdg[x] += dG * 5;
	    if (nextx >= 0 && nextx < skin_image->width)
		nextdg[nextx] += dG;
	    dG *= 7;
	}
    } else if (exact_colors) {
	for (x = 0; x < skin_image->width; x++) {
	    unsigned long p = skin_color[data[x]].pixel;
	    XPutPixel(skin_image, x, skin_y, p);
	}
    } else /* no grayscale display;
	      skin_type == IMGTYPE_COLORMAPPED but no exact colors,
	      or skin_type == IMGTYPE_TRUECOLOR */ {
	int r, g, b, dR = 0, dG = 0, dB = 0;
	dir = ((skin_y & 1) << 1) - 1;
	if (dir == 1) {
	    start = 0;
	    end = skin_image->width;
	} else {
	    start = skin_image->width - 1;
	    end = -1;
	}
	temp = nextdr; nextdr = dr; dr = temp;
	temp = nextdg; nextdg = dg; dg = temp;
	temp = nextdb; nextdb = db; db = temp;
	for (x = start; x != end; x += dir) {
	    if (skin_type == IMGTYPE_COLORMAPPED) {
		unsigned char p = data[x];
		r = skin_cmap[p].r;
		g = skin_cmap[p].g;
		b = skin_cmap[p].b;
	    } else {
		int xx = (x << 2) + 1;
		r = data[xx++];
		g = data[xx++];
		b = data[xx++];
	    }
	    r += (dr[x] + dR) >> 4;
	    if (r < 0) r = 0; else if (r > 255) r = 255;
	    dr[x] = 0;
	    g += (dg[x] + dG) >> 4;
	    if (g < 0) g = 0; else if (g > 255) g = 255;
	    dg[x] = 0;
	    b += (db[x] + dB) >> 4;
	    if (b < 0) b = 0; else if (b > 255) b = 255;
	    db[x] = 0;
	    if (colorcube_size != 0) {
		int index = (((r * (colorcube_size - 1) + 127) / 255)
			* colorcube_size
			+ ((g * (colorcube_size - 1) + 127) / 255))
			* colorcube_size
			+ ((b * (colorcube_size - 1) + 127) / 255);
		dR = r - (skin_color[index].red >> 8);
		dG = g - (skin_color[index].green >> 8);
		dB = b - (skin_color[index].blue >> 8);
		pixel = skin_color[index].pixel;
	    } else {
		int ri = (r * rmax + 127) / 255;
		int gi = (g * gmax + 127) / 255;
		int bi = (b * bmax + 127) / 255;
		pixel = (ri << rmult) + (gi << gmult) + (bi << bmult);
		dR = r - ri * 255 / rmax;
		dG = g - gi * 255 / gmax;
		dB = b - bi * 255 / bmax;
	    }
	    XPutPixel(skin_image, x, skin_y, pixel);
	    prevx = x - dir;
	    nextx = x + dir;
	    if (prevx >= 0 && prevx < skin_image->width) {
		nextdr[prevx] += dR * 3;
		nextdg[prevx] += dG * 3;
		nextdb[prevx] += dB * 3;
	    }
	    nextdr[x] += dR * 5;
	    nextdg[x] += dG * 5;
	    nextdb[x] += dB * 5;
	    if (nextx >= 0 && nextx < skin_image->width) {
		nextdr[nextx] += dR;
		nextdg[nextx] += dG;
		nextdb[nextx] += dB;
	    }
	    dR *= 7;
	    dG *= 7;
	    dB *= 7;
	}
    }

    skin_y++;
}

void skin_finish_image() {
    if (dr != NULL) free(dr);
    if (dg != NULL) free(dg);
    if (db != NULL) free(db);
    if (nextdr != NULL) free(nextdr);
    if (nextdg != NULL) free(nextdg);
    if (nextdb != NULL) free(nextdb);
    dr = dg = db = nextdr = nextdg = nextdb = NULL;
}

void skin_repaint() {
    XPutImage(display, calc_canvas, gc, skin_image,
	      skin.x, skin.y,
	      0, 0,
	      skin.width, skin.height);
}

void skin_repaint_annunciator(int which, int state) {
    if (!display_enabled)
	return;
    SkinAnnunciator *ann = annunciators + (which - 1);
    if (state)
	XPutImage(display, calc_canvas, gc, skin_image,
		  ann->src.x, ann->src.y,
		  ann->disp_rect.x, ann->disp_rect.y,
		  ann->disp_rect.width, ann->disp_rect.height);
    else
	XPutImage(display, calc_canvas, gc, skin_image,
		  ann->disp_rect.x, ann->disp_rect.y,
		  ann->disp_rect.x, ann->disp_rect.y,
		  ann->disp_rect.width, ann->disp_rect.height);
}

void skin_find_key(int x, int y, bool cshift, int *skey, int *ckey) {
    int i;
    if (core_menu()
	    && x >= display_loc.x
	    && x < display_loc.x + 131 * display_scale.x
	    && y >= display_loc.y + 9 * display_scale.y
	    && y < display_loc.y + 16 * display_scale.y) {
	int softkey = (x - display_loc.x) / (22 * display_scale.x) + 1;
	*skey = -1 - softkey;
	*ckey = softkey;
	return;
    }
    for (i = 0; i < nkeys; i++) {
	SkinKey *k = keylist + i;
	int rx = x - k->sens_rect.x;
	int ry = y - k->sens_rect.y;
	if (rx >= 0 && rx < k->sens_rect.width
		&& ry >= 0 && ry < k->sens_rect.height) {
	    *skey = i;
	    *ckey = cshift ? k->shifted_code : k->code;
	    return;
	}
    }
    *skey = -1;
    *ckey = 0;
}

int skin_find_skey(int ckey) {
    int i;
    for (i = 0; i < nkeys; i++)
	if (keylist[i].code == ckey || keylist[i].shifted_code == ckey)
	    return i;
    return -1;
}

unsigned char *skin_find_macro(int ckey) {
    SkinMacro *m = macrolist;
    while (m != NULL) {
	if (m->code == ckey)
	    return m->macro;
	m = m->next;
    }
    return NULL;
}

unsigned char *skin_keymap_lookup(KeySym ks, bool printable,
				  bool ctrl, bool alt, bool shift, bool cshift,
				  bool *exact) {
    int i;
    unsigned char *macro = NULL;
    for (i = 0; i < keymap_length; i++) {
	keymap_entry *entry = keymap + i;
	if (ctrl == entry->ctrl
		&& alt == entry->alt
		&& (printable || shift == entry->shift)
		&& ks == entry->keysym) {
	    macro = entry->macro;
	    if (cshift == entry->cshift) {
		*exact = true;
		return macro;
	    }
	}
    }
    *exact = false;
    return macro;
}

void skin_repaint_key(int key, int state) {
    SkinKey *k;

    if (key >= -7 && key <= -2) {
	/* Soft key */
	if (!display_enabled)
	    // Should never happen -- the display is only disabled during macro
	    // execution, and softkey events should be impossible to generate
	    // in that state. But, just staying on the safe side.
	    return;
	int x, y;
	GC gc = state ? disp_inv_gc : disp_gc;
	key = -1 - key;
	x = (key - 1) * 22 * display_scale.x;
	y = 9 * display_scale.y;
	XPutImage(display, calc_canvas, gc, disp_image,
		  x, y,
		  display_loc.x + x, display_loc.y + y,
		  21 * display_scale.x, 7 * display_scale.y);
	return;
    }

    if (key < 0 || key >= nkeys)
	return;
    k = keylist + key;
    if (state)
	XPutImage(display, calc_canvas, gc, skin_image,
		  k->src.x, k->src.y,
		  k->disp_rect.x, k->disp_rect.y,
		  k->disp_rect.width, k->disp_rect.height);
    else
	XPutImage(display, calc_canvas, gc, skin_image,
		  k->disp_rect.x, k->disp_rect.y,
		  k->disp_rect.x, k->disp_rect.y,
		  k->disp_rect.width, k->disp_rect.height);
}

void skin_display_blitter(const char *bits, int bytesperline, int x, int y,
	                             int width, int height) {
    int h, v;
    int sx = display_scale.x;
    int sy = display_scale.y;

    for (v = y; v < y + height; v++)
	for (h = x; h < x + width; h++) {
	    int pixel =
		    (bits[v * bytesperline + (h >> 3)] & (1 << (h & 7))) != 0;
	    int hh, vv;
	    for (vv = v * sy; vv < (v + 1) * sy; vv++)
		for (hh = h * sx; hh < (h + 1) * sx; hh++)
		    XPutPixel(disp_image, hh, vv, pixel);
	}
    if (allow_paint && display_enabled)
	XPutImage(display, calc_canvas, disp_gc, disp_image,
		  x * sx, y * sy,
		  display_loc.x + x * sx, display_loc.y + y * sy,
		  width * sx, height * sy);
}

void skin_repaint_display() {
    if (display_enabled)
	XPutImage(display, calc_canvas, disp_gc, disp_image,
		  0, 0,
		  display_loc.x, display_loc.y,
		  131 * display_scale.x, 16 * display_scale.y);
}

void skin_display_set_enabled(bool enable) {
    display_enabled = enable;
}
#endif