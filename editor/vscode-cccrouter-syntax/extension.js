const vscode = require('vscode');

// Token types. Order = numeric id used by the builder; never reorder, only append.
//   0 cccPlaceholder  $VAR / ${VAR}            (a powershell variable / a ccc variable ref)
//   1 cccPositional   ^key / ^0                (param marker, in key signature or value)
//   2 cccDefault      =default                 (the "=value" after ^key in a key signature)
//   3 cccCommand      command in command pos.  (cmdlet / exe at the head of a statement)
//   4 cccKeyword      if/foreach/return/...    (powershell language keyword)
//   5 cccParameter    -Name / --long          (a parameter or flag, in argument position)
//   6 cccOperator     ; | & && || -eq -notin  (pipeline/statement separators & word ops)
//   7 cccString       '...' / \"...\"          (a quoted string inside a command value)
const TOKEN_TYPES = [
    'cccPlaceholder', 'cccPositional', 'cccDefault',
    'cccCommand', 'cccKeyword', 'cccParameter', 'cccOperator', 'cccString'
];
const T = {
    PLACEHOLDER: 0, POSITIONAL: 1, DEFAULT: 2,
    COMMAND: 3, KEYWORD: 4, PARAMETER: 5, OPERATOR: 6, STRING: 7
};
const LEGEND = new vscode.SemanticTokensLegend(TOKEN_TYPES);
const SELECTOR = { pattern: '**/cccrouter.json' };

// $VAR / ${VAR}; anchored so it can be tested at an arbitrary offset.
const PLACEHOLDER_AT = /^\$\{[A-Za-z_]\w*\}|^\$[A-Za-z_]\w*/;
// ^key (^name or ^0), optionally followed by a default "=value" in a key signature.
// the default stops at $ / whitespace / braces / quote so a $VAR default (^1=$ENV) is
// left to the placeholder rule and the token types never overlap.
const POSITIONAL_SIG = /\^(?:[A-Za-z_]\w*|\d+)(=[^\s${}"]+)?/g;
const POSITIONAL_AT = /^\^(?:[A-Za-z_]\w*|\d+)/;
const PLACEHOLDER_G = /\$\{[A-Za-z_]\w*\}|\$[A-Za-z_]\w*/g;
const FLAG_AT = /^--?[A-Za-z][\w-]*/;

// powershell language keywords (lower-cased for comparison).
const KEYWORDS = new Set([
    'if', 'else', 'elseif', 'switch', 'foreach', 'for', 'while', 'do', 'until',
    'return', 'break', 'continue', 'try', 'catch', 'finally', 'throw', 'function',
    'filter', 'param', 'begin', 'process', 'end', 'in', 'trap', 'class', 'enum',
    'data', 'dynamicparam', 'exit', 'using'
]);
// powershell word operators (lower-cased, with leading dash) — these read as -Name
// flags but are really operators, so they get the operator colour, not parameter.
const WORD_OPERATORS = new Set([
    '-eq', '-ne', '-gt', '-ge', '-lt', '-le', '-like', '-notlike', '-match',
    '-notmatch', '-contains', '-notcontains', '-in', '-notin', '-replace', '-split',
    '-join', '-and', '-or', '-xor', '-not', '-band', '-bor', '-bnot', '-bxor',
    '-is', '-isnot', '-as', '-shl', '-shr', '-f'
]);

function matchLen(re, text, pos, end) {
    re.lastIndex = 0;
    const m = re.exec(text.slice(pos, end));
    return m ? m[0].length : 0;
}

const isSpace = (c) => c === ' ' || c === '\t' || c === '\r' || c === '\n';

// lex a key signature ("uncommit ^0=1 ^1=--soft", "user ^name ^email"): ^key markers
// become cccPositional, the "=value" tail cccDefault, and any $VAR default cccPlaceholder.
function lexKeySignature(text, start, end, out) {
    const seg = text.slice(start, end);
    let m;
    POSITIONAL_SIG.lastIndex = 0;
    while ((m = POSITIONAL_SIG.exec(seg)) !== null) {
        const def = m[1];
        const markerLen = m[0].length - (def ? def.length : 0);
        out.push({ start: start + m.index, length: markerLen, type: T.POSITIONAL });
        if (def) out.push({ start: start + m.index + markerLen, length: def.length, type: T.DEFAULT });
    }
    PLACEHOLDER_G.lastIndex = 0;
    while ((m = PLACEHOLDER_G.exec(seg)) !== null) {
        out.push({ start: start + m.index, length: m[0].length, type: T.PLACEHOLDER });
    }
}

// lex a command template value with a small powershell-flavoured scanner. single line
// (JSON string values never contain raw newlines), so no cross-line state is needed.
// $VAR and ^key are carved out for the placeholder/positional rules so nothing overlaps.
function lexCommandValue(text, start, end, out) {
    let i = start;
    let cmdPos = true; // are we at a command position (statement head)?
    while (i < end) {
        const ch = text[i];
        if (isSpace(ch)) { i++; continue; }

        if (ch === '$') {
            const n = matchLen(PLACEHOLDER_AT, text, i, end);
            if (n) { out.push({ start: i, length: n, type: T.PLACEHOLDER }); i += n; cmdPos = false; continue; }
        }
        if (ch === '^') {
            const n = matchLen(POSITIONAL_AT, text, i, end);
            if (n) { out.push({ start: i, length: n, type: T.POSITIONAL }); i += n; cmdPos = false; continue; }
        }

        // statement separators / pipeline -> operator, next token is a command again
        if (ch === ';') { out.push({ start: i, length: 1, type: T.OPERATOR }); i++; cmdPos = true; continue; }
        if (ch === '|') { const l = text[i + 1] === '|' ? 2 : 1; out.push({ start: i, length: l, type: T.OPERATOR }); i += l; cmdPos = true; continue; }
        if (ch === '&') { const l = text[i + 1] === '&' ? 2 : 1; out.push({ start: i, length: l, type: T.OPERATOR }); i += l; cmdPos = true; continue; }

        // grouping / scriptblock: re-open a command position inside, close it after
        if (ch === '(' || ch === '{') { i++; cmdPos = true; continue; }
        if (ch === ')' || ch === '}') { i++; cmdPos = false; continue; }

        // single-quoted string (literal in JSON; '' is an escaped quote)
        if (ch === "'") {
            let j = i + 1;
            while (j < end) { if (text[j] === "'") { if (text[j + 1] === "'") { j += 2; continue; } break; } j++; }
            const e = j < end ? j + 1 : end;
            out.push({ start: i, length: e - i, type: T.STRING }); i = e; cmdPos = false; continue;
        }
        // double-quoted string, JSON-escaped as \" ... \"; $VAR inside is carved out
        if (ch === '\\' && text[i + 1] === '"') {
            let j = i + 2, segStart = i;
            while (j < end) {
                if (text[j] === '\\' && text[j + 1] === '"') { j += 2; break; } // closing \"
                if (text[j] === '$') {
                    const n = matchLen(PLACEHOLDER_AT, text, j, end);
                    if (n) {
                        if (j > segStart) out.push({ start: segStart, length: j - segStart, type: T.STRING });
                        out.push({ start: j, length: n, type: T.PLACEHOLDER });
                        j += n; segStart = j; continue;
                    }
                }
                if (text[j] === '\\') { j += 2; continue; }
                j++;
            }
            const e = Math.min(j, end);
            if (e > segStart) out.push({ start: segStart, length: e - segStart, type: T.STRING });
            i = e; cmdPos = false; continue;
        }

        // -Name flag / word operator, only in argument position
        if (ch === '-' && !cmdPos) {
            const n = matchLen(FLAG_AT, text, i, end);
            if (n) {
                const word = text.substr(i, n).toLowerCase();
                out.push({ start: i, length: n, type: WORD_OPERATORS.has(word) ? T.OPERATOR : T.PARAMETER });
                i += n; continue;
            }
        }

        // bareword: a run up to the next separator / quote / placeholder boundary
        let j = i;
        while (j < end) {
            const c = text[j];
            if (isSpace(c) || c === ';' || c === '|' || c === '&' || c === "'"
                || c === '(' || c === ')' || c === '{' || c === '}'
                || c === '$' || c === '^' || (c === '\\' && text[j + 1] === '"')) break;
            j++;
        }
        if (j === i) { i++; continue; }
        if (cmdPos) {
            const word = text.substring(i, j).toLowerCase();
            out.push({ start: i, length: j - i, type: KEYWORDS.has(word) ? T.KEYWORD : T.COMMAND });
            cmdPos = false;
        }
        // argument barewords keep the default JSON string colour (no token emitted)
        i = j;
    }
}

// single linear pass over the document: tracks JSON structure so we know which strings
// are keys vs values and which top-level section ("commands" / "variables") they live in.
// only command *values* get the powershell lexer; keys get the signature lexer.
function collectTokens(text) {
    const out = [];
    const stack = []; // frames: { container, key, currentKey }
    const section = () => (stack.length >= 2 ? stack[1].key : null);
    let i = 0;
    const n = text.length;
    while (i < n) {
        const ch = text[i];
        if (ch === '/' && text[i + 1] === '/') { i += 2; while (i < n && text[i] !== '\n') i++; continue; }
        if (ch === '/' && text[i + 1] === '*') { i += 2; while (i < n && !(text[i] === '*' && text[i + 1] === '/')) i++; i += 2; continue; }
        if (ch === '{' || ch === '[') {
            const key = stack.length ? stack[stack.length - 1].currentKey : null;
            stack.push({ container: ch === '{' ? 'object' : 'array', key, currentKey: null });
            i++; continue;
        }
        if (ch === '}' || ch === ']') { stack.pop(); i++; continue; }
        if (ch === '"') {
            let j = i + 1;
            while (j < n) { if (text[j] === '\\') { j += 2; continue; } if (text[j] === '"') break; j++; }
            const contentStart = i + 1;
            const contentEnd = j;            // index of closing quote (or n)
            let k = (j < n ? j + 1 : n);     // peek the next significant char
            while (k < n && isSpace(text[k])) k++;
            const isKey = text[k] === ':';
            const frame = stack[stack.length - 1];
            if (isKey) {
                if (frame && frame.container === 'object') frame.currentKey = text.slice(contentStart, contentEnd);
                lexKeySignature(text, contentStart, contentEnd, out);
            } else if (section() === 'commands') {
                lexCommandValue(text, contentStart, contentEnd, out);
            }
            i = (j < n ? j + 1 : n);
            continue;
        }
        i++;
    }
    return out;
}

const provider = {
    provideDocumentSemanticTokens(document) {
        const builder = new vscode.SemanticTokensBuilder(LEGEND);
        const tokens = collectTokens(document.getText());
        tokens.sort((a, b) => a.start - b.start);
        for (const t of tokens) {
            const pos = document.positionAt(t.start);
            builder.push(pos.line, pos.character, t.length, t.type);
        }
        return builder.build();
    }
};

// the colour setting we seed/reset. under the 'editor' config section it is just
// the leaf key; inside package.json's configurationDefaults it is the dotted form.
const SEMANTIC_KEY = 'semanticTokenColorCustomizations';
const SEMANTIC_DOTTED = 'editor.semanticTokenColorCustomizations';

// read the shipped default rules back out of *this* extension's package.json
// (contributes.configurationDefaults) so the commands have a single source of
// truth and can never drift from the colours the extension already provides.
// returned as a deep copy — callers mutate it freely.
function defaultRules(context) {
    const rules = context.extension.packageJSON
        ?.contributes?.configurationDefaults?.[SEMANTIC_DOTTED]?.rules;
    return rules ? JSON.parse(JSON.stringify(rules)) : {};
}

// "CCC Router Syntax: Customize Colors" — seed any missing ccc* rule into the
// user-level settings.json (never overwriting a colour the user already set),
// then open settings.json to edit. when every rule is already present the write
// is skipped and it simply opens the file.
async function customizeColors(context) {
    const cfg = vscode.workspace.getConfiguration('editor');
    const current = cfg.inspect(SEMANTIC_KEY)?.globalValue;
    const next = current ? JSON.parse(JSON.stringify(current)) : {};
    if (!next.rules) next.rules = {};
    let changed = false;
    for (const [name, rule] of Object.entries(defaultRules(context))) {
        if (!(name in next.rules)) { next.rules[name] = rule; changed = true; }
    }
    if (changed) await cfg.update(SEMANTIC_KEY, next, vscode.ConfigurationTarget.Global);
    await vscode.commands.executeCommand('workbench.action.openSettingsJson');
}

// "CCC Router Syntax: Reset Colors" — drop only the ccc* rules from the
// user-level setting so the colours fall back to the extension defaults. any
// non-ccc rule the user added is left intact; if nothing else remains the whole
// setting is cleared so no empty `{ "rules": {} }` husk is left behind.
async function resetColors(context) {
    const cfg = vscode.workspace.getConfiguration('editor');
    const current = cfg.inspect(SEMANTIC_KEY)?.globalValue;
    if (!current || !current.rules) {
        vscode.window.showInformationMessage('CCC Router Syntax: no custom colours to reset.');
        return;
    }
    const next = JSON.parse(JSON.stringify(current));
    let removed = 0;
    for (const name of Object.keys(defaultRules(context))) {
        if (name in next.rules) { delete next.rules[name]; removed++; }
    }
    if (Object.keys(next.rules).length === 0) delete next.rules;
    const empty = Object.keys(next).length === 0;
    await cfg.update(SEMANTIC_KEY, empty ? undefined : next, vscode.ConfigurationTarget.Global);
    vscode.window.showInformationMessage(
        removed ? `CCC Router Syntax: reset ${removed} colour rule(s) to defaults.`
                : 'CCC Router Syntax: no ccc colours were set.');
}

function activate(context) {
    context.subscriptions.push(
        vscode.languages.registerDocumentSemanticTokensProvider(SELECTOR, provider, LEGEND),
        vscode.commands.registerCommand('cccrouter.customizeColors', () => customizeColors(context)),
        vscode.commands.registerCommand('cccrouter.resetColors', () => resetColors(context))
    );
}

module.exports = { activate };
