const vscode = require('vscode');

const TOKEN_TYPES = ['cccPlaceholder', 'cccPositional', 'cccDefault'];
const LEGEND = new vscode.SemanticTokensLegend(TOKEN_TYPES);
const SELECTOR = { pattern: '**/cccrouter.json' };

const PLACEHOLDER_RE = /\$\{[A-Za-z_]\w*\}|\$[A-Za-z_]\w*/g;
// positional marker ^n, optionally followed by a default "=value" in a key
// signature ("uncommit ^0=1 ^1=--soft"); a bare ^n also appears in a value
// ("git reset HEAD~^0 ^1"). the ^n marker becomes cccPositional and the =value
// becomes cccDefault. the value match stops at $ / whitespace / braces / quote,
// so a $VAR default (^1=$ENVIRONMENT) is left to PLACEHOLDER_RE and the three
// token types never overlap.
const POSITIONAL_RE = /\^\d+(=[^\s${}"]+)?/g;

function collectMatches(out, text, regex, tokenType) {
    regex.lastIndex = 0;
    let match;
    while ((match = regex.exec(text)) !== null) {
        out.push({ index: match.index, length: match[0].length, tokenType });
    }
}

// like collectMatches, but splits each "^n=value" hit into the ^n marker
// (cccPositional) and the "=value" default (cccDefault).
function collectPositionals(out, text) {
    POSITIONAL_RE.lastIndex = 0;
    let match;
    while ((match = POSITIONAL_RE.exec(text)) !== null) {
        const defaultPart = match[1];
        const markerLength = match[0].length - (defaultPart ? defaultPart.length : 0);
        out.push({ index: match.index, length: markerLength, tokenType: 1 });
        if (defaultPart) {
            out.push({ index: match.index + markerLength, length: defaultPart.length, tokenType: 2 });
        }
    }
}

const provider = {
    provideDocumentSemanticTokens(document) {
        const builder = new vscode.SemanticTokensBuilder(LEGEND);
        for (let line = 0; line < document.lineCount; line++) {
            const text = document.lineAt(line).text;
            const matches = [];
            collectMatches(matches, text, PLACEHOLDER_RE, 0);
            collectPositionals(matches, text);
            matches.sort((a, b) => a.index - b.index);
            for (const m of matches) {
                builder.push(line, m.index, m.length, m.tokenType);
            }
        }
        return builder.build();
    }
};

function activate(context) {
    context.subscriptions.push(
        vscode.languages.registerDocumentSemanticTokensProvider(SELECTOR, provider, LEGEND)
    );
}

module.exports = { activate };
