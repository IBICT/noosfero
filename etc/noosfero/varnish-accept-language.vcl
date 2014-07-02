C{

/* ------------------------------------------------------------------ */
/* THIS FILE IS AUTOMATICALLY GENERATED BY ./gen_vcl.pl. DO NOT EDIT. */

/*
 * Accept-language header normalization
 *
 * - Parses client Accept-Language HTTP header
 * - Tries to find the best match with the supported languages
 * - Writes the best match as req.http.X-Varnish-Accept-Language
 *
 * First version: Cosimo, 21/Jan/2010
 * Last update:   Cosimo, 03/Nov/2011
 *
 * http://github.com/cosimo/varnish-accept-language
 *
 */

#include <ctype.h>  /* isupper */
#include <stdio.h>
#include <stdlib.h> /* qsort */
#include <string.h>

#define DEFAULT_LANGUAGE "en"
#define SUPPORTED_LANGUAGES ":de:eo:es:fr:hy:it:pt:ru:"

#define vcl_string char
#define LANG_LIST_SIZE 16
#define HDR_MAXLEN 256
#define LANG_MAXLEN 8
#define RETURN_LANG(x) { \
    strncpy(lang, x, LANG_MAXLEN); \
    return; \
}
#define RETURN_DEFAULT_LANG RETURN_LANG(DEFAULT_LANGUAGE)
#define PUSH_LANG(x,y) { \
    /* fprintf(stderr, "Pushing lang [%d] %s %.4f\n", curr_lang, x, y); */ \
    /* We have to copy, otherwise root_lang will be the same every time */ \
    strncpy(pl[curr_lang].lang, x, LANG_MAXLEN); \
    pl[curr_lang].q = y;       \
    curr_lang++;               \
}

struct lang_list {
    vcl_string lang[LANG_MAXLEN];
    float q;
};

/* In-place lowercase of a string */
static void strtolower(char *s) {
    register char *c;
    for (c=s; *c; c++) {
        if (isupper(*c)) {
            *c = tolower(*c);
        }
    }
    return;
}

/* Checks if a given language is in the static list of the ones we support */
int is_supported(vcl_string *lang) {
    vcl_string *supported_languages = SUPPORTED_LANGUAGES;
    vcl_string match_str[LANG_MAXLEN + 3] = "";  /* :, :, \0 = 3 */
    int is_supported = 0;

    /* We want to match 'zh-cn' and 'zh-CN' too */
    strtolower(lang);

    /* Search ":<lang>:" in supported languages string */
    strncpy(match_str, ":", 1);
    strncat(match_str, lang, LANG_MAXLEN);
    strncat(match_str, ":\0", 2);

    if (strstr(supported_languages, match_str))
        is_supported = 1;

    return is_supported;
}

/* Used by qsort() below */
int sort_by_q(const void *x, const void *y) {
    struct lang_list *a = (struct lang_list *)x;
    struct lang_list *b = (struct lang_list *)y;
    if (a->q > b->q) return -1;
    if (a->q < b->q) return 1;
    return 0;
}

/* Reads Accept-Language, parses it, and finds the first match
   among the supported languages. In case of no match,
   returns the default language.
*/
void select_language(const vcl_string *incoming_header, char *lang) {

    struct lang_list pl[LANG_LIST_SIZE];
    vcl_string *lang_tok = NULL;
    vcl_string root_lang[3];
    vcl_string *header;
    vcl_string header_copy[HDR_MAXLEN];
    vcl_string *pos = NULL;
    vcl_string *q_spec = NULL;
    unsigned int curr_lang = 0, i = 0;
    float q;

    /* Empty or default string, return default language immediately */
    if (
        !incoming_header
        || (0 == strcmp(incoming_header, "en-US"))
        || (0 == strcmp(incoming_header, "en-GB"))
        || (0 == strcmp(incoming_header, DEFAULT_LANGUAGE))
        || (0 == strcmp(incoming_header, ""))
    )
        RETURN_DEFAULT_LANG;

    /* Tokenize Accept-Language */
    header = strncpy(header_copy, incoming_header, sizeof(header_copy));

    while ((lang_tok = strtok_r(header, " ,", &pos))) {

        q = 1.0;

        if ((q_spec = strstr(lang_tok, ";q="))) {
            /* Truncate language name before ';' */
            *q_spec = '\0';
            /* Get q value */
            sscanf(q_spec + 3, "%f", &q);
        }

        /* Wildcard language '*' should be last in list */
        if ((*lang_tok) == '*') q = 0.0;

        /* Push in the prioritized list */
        PUSH_LANG(lang_tok, q);

        /* For cases like 'en-GB', we also want the root language in the final list */
        if ('-' == lang_tok[2]) {
            root_lang[0] = lang_tok[0];
            root_lang[1] = lang_tok[1];
            root_lang[2] = '\0';
            PUSH_LANG(root_lang, q - 0.001);
        }

        /* For strtok_r() to proceed from where it left off */
        header = NULL;

        /* Break out if stored max no. of languages */
        if (curr_lang >= LANG_LIST_SIZE)
            break;
    }

    /* Sort by priority */
    qsort(pl, curr_lang, sizeof(struct lang_list), &sort_by_q);

    /* Match with supported languages */
    for (i = 0; i < curr_lang; i++) {
        if (is_supported(pl[i].lang))
            RETURN_LANG(pl[i].lang);
    }

    RETURN_DEFAULT_LANG;
}

/* Reads req.http.Accept-Language and writes X-Varnish-Accept-Language */
void vcl_rewrite_accept_language(const struct sess *sp) {
    vcl_string *in_hdr;
    vcl_string lang[LANG_MAXLEN];

    /* Get Accept-Language header from client */
    in_hdr = VRT_GetHdr(sp, HDR_REQ, "\020Accept-Language:");

    /* Normalize and filter out by list of supported languages */
    memset(lang, 0, sizeof(lang));
    select_language(in_hdr, lang);

    /* By default, use a different header name: don't mess with backend logic */
    VRT_SetHdr(sp, HDR_REQ, "\032X-Varnish-Accept-Language:", lang, vrt_magic_string_end);

    return;
}

/* vim: syn=c ts=4 et sts=4 sw=4 tw=0
*/

/* THIS FILE IS AUTOMATICALLY GENERATED BY ./gen_vcl.pl. DO NOT EDIT. */
/* ------------------------------------------------------------------ */
}C

sub vcl_recv {
  C{
    vcl_rewrite_accept_language(sp);
  }C
}

sub vcl_fetch {
  if (beresp.http.Vary) {
    set beresp.http.Vary = beresp.http.Vary + ", X-Varnish-Accept-Language";
  } else {
    set beresp.http.Vary = "X-Varnish-Accept-Language";
  }
}

