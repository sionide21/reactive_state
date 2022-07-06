# Used by "mix format"
locals_without_parens = [
  input: 1,
  input: 2,
  defcomputed: 2,
  defcomputedp: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  export: [
    locals_without_parens: locals_without_parens
  ],
  locals_without_parens: locals_without_parens
]
