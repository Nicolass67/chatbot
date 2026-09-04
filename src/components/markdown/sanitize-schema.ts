import { defaultSchema } from "hast-util-sanitize";
import type { Schema } from "hast-util-sanitize";

const katexClass =
  /^katex|^m[a-z]|^vlist|^base|^strut|^sizing|^fontsize-ensurer|^mspace|^msupsub|^pstrut|^mord|^mrel|^mop|^mbin|^mopen|^mclose|^mpunct|^minner|^delimsizing|^sqrt|^hide-tail|^stretchy|^arraycolsep|^col-align-|^accent-|^mtight|^reset-|^rule|^overline|^underline|^hdashline|^rlap|^llap|^clap|^nobreak|^mathnormal|^mathit|^mathbf|^mathbb|^mathcal|^mathfrak|^mathscr|^text|^textrm|^textit|^textsf|^texttt|^textmd|^textup|^operatorname|^boxed|^tag|^eqn-num|^left|^right|^brace|^mfrac|^mtable|^mtr|^mtd|^mrow|^mstyle|^mphantom|^mpadded|^menclose|^semantics|^annotation|^math$/;

/** Allows highlight.js + KaTeX while keeping GitHub-style sanitation. */
export const markdownSanitizeSchema: Schema = {
  ...defaultSchema,
  tagNames: [
    ...(defaultSchema.tagNames ?? []),
    "math",
    "semantics",
    "mrow",
    "mi",
    "mn",
    "mo",
    "msup",
    "msub",
    "mfrac",
    "msqrt",
    "mroot",
    "mtable",
    "mtr",
    "mtd",
    "mtext",
    "mspace",
    "mstyle",
    "mphantom",
    "mpadded",
    "menclose",
    "annotation",
    "svg",
    "line",
    "path",
    "g",
    "rect",
  ],
  attributes: {
    ...defaultSchema.attributes,
    code: [
      ...(defaultSchema.attributes?.code ?? []),
      ["className", /^language-[\w-]+$/],
      ["className", /^hljs$/],
    ],
    pre: [["className", /^hljs$/]],
    span: [
      ...(defaultSchema.attributes?.span ?? []),
      ["className", katexClass],
      ["style"],
    ],
    div: [...(defaultSchema.attributes?.div ?? []), ["className", katexClass]],
    math: [
      ["xmlns", "http://www.w3.org/1998/Math/MathML"],
      ["display", "block"],
      ["display", "inline"],
    ],
    semantics: [["encoding", "MathML-Content"]],
    annotation: [["encoding"]],
    svg: [
      ["xmlns", "http://www.w3.org/2000/svg"],
      ["width"],
      ["height"],
      ["viewBox"],
      ["focusable"],
      ["role"],
      ["aria-hidden"],
    ],
    line: [["x1"], ["y1"], ["x2"], ["y2"]],
    path: [["d"]],
    g: [["transform"]],
    rect: [["width"], ["height"], ["x"], ["y"]],
  },
};
