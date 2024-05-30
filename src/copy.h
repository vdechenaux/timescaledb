/*
 * This file and its contents are licensed under the Apache License 2.0.
 * Please see the included NOTICE for copyright information and
 * LICENSE-APACHE for a copy of the license.
 */
#pragma once

#include <postgres.h>
#include <nodes/parsenodes.h>
#include <access/xact.h>
#include <access/relscan.h>
#include <executor/executor.h>
#include <commands/copy.h>
#include <storage/lockdefs.h>

typedef struct ChunkDispatch ChunkDispatch;
typedef struct CopyChunkState CopyChunkState;
typedef struct Hypertable Hypertable;

typedef bool (*CopyFromFunc)(CopyChunkState *ccstate, ExprContext *econtext, Datum *values,
							 bool *nulls);

typedef struct CopyChunkState
{
	Relation rel;
	EState *estate;
	ChunkDispatch *dispatch;
	CopyFromFunc next_copy_from;
	CopyFromState cstate;
	TableScanDesc scandesc;
	Node *where_clause;
} CopyChunkState;

extern void timescaledb_DoCopy(const CopyStmt *stmt, const char *queryString, uint64 *processed,
							   Hypertable *ht);
extern void timescaledb_move_from_table_to_chunks(Hypertable *ht, LOCKMODE lockmode);

#if PG13

/*
 * Represents the different source/dest cases we need to worry about at
 * the bottom level
 */
typedef enum CopyDest
{
        COPY_FILE,                                      /* to/from file (or a piped program) */
        COPY_OLD_FE,                            /* to/from frontend (2.0 protocol) */
        COPY_NEW_FE,                            /* to/from frontend (3.0 protocol) */
        COPY_CALLBACK                           /* to/from callback function */
} CopyDest;


/*
 *      Represents the end-of-line terminator type of the input
 */
typedef enum EolType
{
        EOL_UNKNOWN,
        EOL_NL,
        EOL_CR,
        EOL_CRNL
} EolType;



typedef struct CopyStateData
{
        /* low-level state data */
        CopyDest        copy_dest;              /* type of copy source/destination */
        FILE       *copy_file;          /* used if copy_dest == COPY_FILE */
        StringInfo      fe_msgbuf;              /* used for all dests during COPY TO, only for
                                                                 * dest == COPY_NEW_FE in COPY FROM */
        bool            is_copy_from;   /* COPY TO, or COPY FROM? */
        bool            reached_eof;    /* true if we read to end of copy data (not
                                                                 * all copy_dest types maintain this) */
        //EolType         eol_type;               /* EOL type of input */
        int                     file_encoding;  /* file or remote side's character encoding */
        bool            need_transcoding;       /* file encoding diff from server? */
        bool            encoding_embeds_ascii;  /* ASCII can be non-first byte? */

        /* parameters from the COPY command */
        Relation        rel;                    /* relation to copy to or from */
        QueryDesc  *queryDesc;          /* executable query to copy from */
        List       *attnumlist;         /* integer list of attnums to copy */
        char       *filename;           /* filename, or NULL for STDIN/STDOUT */
        bool            is_program;             /* is 'filename' a program to popen? */
        copy_data_source_cb data_source_cb; /* function for reading data */
        bool            binary;                 /* binary format? */
        bool            freeze;                 /* freeze rows on loading? */
        bool            csv_mode;               /* Comma Separated Value format? */
        bool            header_line;    /* CSV header line? */
        char       *null_print;         /* NULL marker string (server encoding!) */
        int                     null_print_len; /* length of same */
        char       *null_print_client;  /* same converted to file encoding */
        char       *delim;                      /* column delimiter (must be 1 byte) */
        char       *quote;                      /* CSV quote char (must be 1 byte) */
        char       *escape;                     /* CSV escape char (must be 1 byte) */
        List       *force_quote;        /* list of column names */
        bool            force_quote_all;        /* FORCE_QUOTE *? */
        bool       *force_quote_flags;  /* per-column CSV FQ flags */
        List       *force_notnull;      /* list of column names */
        bool       *force_notnull_flags;        /* per-column CSV FNN flags */
        List       *force_null;         /* list of column names */
        bool       *force_null_flags;   /* per-column CSV FN flags */
        bool            convert_selectively;    /* do selective binary conversion? */
        List       *convert_select; /* list of column names (can be NIL) */
        bool       *convert_select_flags;       /* per-column CSV/TEXT CS flags */
        Node       *whereClause;        /* WHERE condition (or NULL) */

        /* these are just for error messages, see CopyFromErrorCallback */
        const char *cur_relname;        /* table name for error messages */
        uint64          cur_lineno;             /* line number for error messages */
        const char *cur_attname;        /* current att for error messages */
        const char *cur_attval;         /* current att value for error messages */

        /*
         * Working state for COPY TO/FROM
         */
        MemoryContext copycontext;      /* per-copy execution context */

        /*
         * Working state for COPY TO
         */
        FmgrInfo   *out_functions;      /* lookup info for output functions */
        MemoryContext rowcontext;       /* per-row evaluation context */
 /*
         * Working state for COPY FROM
         */
        AttrNumber      num_defaults;
        FmgrInfo   *in_functions;       /* array of input functions for each attrs */
        Oid                *typioparams;        /* array of element types for in_functions */
        int                *defmap;                     /* array of default att numbers */
        ExprState **defexprs;           /* array of default att expressions */
        bool            volatile_defexprs;      /* is any of defexprs volatile? */
        List       *range_table;
        ExprState  *qualexpr;

        TransitionCaptureState *transition_capture;

        /*
         * These variables are used to reduce overhead in textual COPY FROM.
         *
         * attribute_buf holds the separated, de-escaped text for each field of
         * the current line.  The CopyReadAttributes functions return arrays of
         * pointers into this buffer.  We avoid palloc/pfree overhead by re-using
         * the buffer on each cycle.
         */
        StringInfoData attribute_buf;

        /* field raw data pointers found by COPY FROM */

        int                     max_fields;
        char      **raw_fields;

        /*
         * Similarly, line_buf holds the whole input line being processed. The
         * input cycle is first to read the whole line into line_buf, convert it
         * to server encoding there, and then extract the individual attribute
         * fields into attribute_buf.  line_buf is preserved unmodified so that we
         * can display it in error messages if appropriate.
         */
        StringInfoData line_buf;
        bool            line_buf_converted; /* converted to server encoding? */
        bool            line_buf_valid; /* contains the row being processed? */

        /*
         * Finally, raw_buf holds raw data read from the data source (file or
         * client connection).  CopyReadLine parses this data sufficiently to
         * locate line boundaries, then transfers the data to line_buf and
         * converts it.  Note: we guarantee that there is a \0 at
         * raw_buf[raw_buf_len].
         */
#define RAW_BUF_SIZE 65536              /* we palloc RAW_BUF_SIZE+1 bytes */
        char       *raw_buf;
        int                     raw_buf_index;  /* next byte to process */
        int                     raw_buf_len;    /* total # of bytes stored */
} CopyStateData;




#endif
