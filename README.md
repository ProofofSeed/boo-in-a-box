# Boo in a Box

In this short technical paper, we discuss how the ZK Boo protocol can be leveraged to produce zero-knowledge proofs for secure elements — such as smart cards and hardware wallets — where stringent constraints on computational resources rule out most general-purpose ZK techniques.

## Compilation

To install Typst, see instructions on the [Typst GitHub repo](https://github.com/typst/typst).

To compile the paper:

```sh
# Compiles to `paper.pdf`
typst compile paper.typ
```

To watch source file while editing and automatically recompile changes:

```sh
typst watch paper.typ
```
