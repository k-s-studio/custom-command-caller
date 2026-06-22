const vscode = require('vscode');

const TOKEN_TYPES = ['cccPlaceholder', 'cccPositional'];
const LEGEND = new vscode.SemanticTokensLegend(TOKEN_TYPES);
const SELECTOR = { pattern: '**/cccrouter.json' };

const PLACEHOLDER_RE = /\$\{[A-Za-z_]\w*\}|\$[A-Za-z_]\w*/g;
// positional marker ^n, both in a key signature ("uncommit ^0=1 ^1=--soft") and
// in a value ("git reset HEAD~^0 ^1"). only the ^n marker is colored; any $VAR in
// a default (^1=$ENVIRONMENT) is left to PLACEHOLDER_RE so the two never overlap.
const POSITIONAL_RE = /\^\d+/g;

function collectMatches(out, text, regex, tokenType) {
    regex.lastIndex = 0;
    let match;
    while ((match = regex.exec(text)) !== null) {
        out.push({ index: match.index, length: match[0].length, tokenType });
    }
}

const provider = {
    provideDocumentSemanticTokens(document) {
        const builder = new vscode.SemanticTokensBuilder(LEGEND);
        for (let line = 0; line < document.lineCount; line++) {
            const text = document.lineAt(line).text;
            const matches = [];
            collectMatches(matches, text, PLACEHOLDER_RE, 0);
            collectMatches(matches, text, POSITIONAL_RE, 1);
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
