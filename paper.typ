#let defn(text) = strong(text)

#import "template.typ": template
#show: template.with(
  title: [
    Boo in a Box: ZK Proofs for Secure Elements
  ],
  abstract: [
    We discuss how the ZK Boo protocol @zkboo2016 @picnic2017 can be leveraged to produce zero-knowledge proofs for secure elements --- such as smart cards and hardware wallets --- where stringent constraints on computational resources rule out most general-purpose ZK techniques.

    #align(center)[#text(size: 10pt)[Draft #datetime.today().display("[day] [month repr:short] [year]")]]
  ],
  author-block: [
    #table(
      columns: (50%, 50%),
      [
        Stefano Gogioso
        #set text(size: 1em - 3pt)
        \ Hashberg
      ],
      [
        Nicolò Chiappori
        #set text(size: 1em - 3pt)
        \ Hashberg
      ],
    )
  ],
  accent-color: rgb("#7e2e84"),
)

// #set heading(numbering: none)
#set math.equation(numbering: none)

= Introduction

Secure elements --- such as smart cards and hardware wallets --- are widely used to store sensitive data and perform critical computations in a tamper-resistant environment.
However, these devices often impose a number of stringent limitations on computational resources: 8-bit, 16-bit or 32-bit architecture; clock speeds in the tens of MHz; cache limited to a few KB; RAM limited to a few dozen KB; ROM/flash limited to a few hundred KB; communication throughput limited to hundreds of KB/s.
//; hardware-acceleration limited to a small set of cryptographic primitives.

As an example, we consider the ST33K MCU by STMicroelectronics @st33k, a 32-bit ARM Cortex-M35P platform with 70MHz clock, 2KB of cache and 64KB of RAM, used in the 2025 Ledger Flex wallet.
Available hardware-accelerated cryptographic primitives are essentially limited to RSA, elliptic curve cryptography (ECC), the SHA/Keccak family of hash functions, DES and AES.
In early practical experiments with user-space Ledger apps, available RAM appears to be limited to \~30KB, with a further limitation of \~7.5KB on maximum heap allocation.

The memory constraints alone rule out the vast majority of modern general-purpose, public-verifier ZK protocols, at least for computations other than ones of trivially short length.
An important exception is represented by MPC-in-the-Head (MPCitH) protocols @ikos2007 such as ZKBoo @zkboo2016 @picnic2017, where succinctness on the verifier side is traded for a significantly lighter workload on the prover side.
Subsequent MPCitH developments @katz2018 @baum2019 @turboikos2021 improve signature size, verification time and prover performance, but they do so at the expense of additional complexity and higher memory footprint, making them less attractive than the original formulation in the context of secure elements.

In @sec:zkboo, we recap the ZKBoo protocol.
In @sec:implementation, we discuss how a careful implementation of ZKBoo prover and verifier can come to within a small constant factor of the minimum memory requirements for the computation that is being proved, independently of trace length or the security parameter of the proof.

One limitation of ZKBoo is that proofs are not succinct, making them unsuitable for applications --- such as on-chain verification --- where trace length of the verifier is a limiting factor.
In @sec:succinct-lifting, we briefly discuss how this limitation could be overcome, by producing succinct ZK proofs via recursive verification outside of the secure element.

#pagebreak()


= The ZKBoo Protocol <sec:zkboo>

ZKBoo @zkboo2016 @picnic2017 is an MPCitH protocol @ikos2007 for binary circuits, with zero-knowledge derived from the 2-privacy property of a simulated 3-party computation employing a (3,3) XOR-based secret-sharing scheme.
For the binary case, the protocol is originally formulated in terms of single-bit operations --- in other words, field operations over $"GF"(2)$ --- but the way in which the MPC operations are defined makes it trivial to extend support to the following bitwise operations on arbitrary word sizes:

- bitwise NOT $w_b := not w_a$;
- bitwise XOR $w_c := w_a xor w_b$;
- bitwise XOR-CONST, i.e. XOR with a constant $w_b := w_a xor k$;
- bitwise AND $w_c := w_a and w_b$;
- bitwise AND-CONST, i.e. AND with a constant $w_b := w_a and k$;
- XOR-affine transformations $w_b := phi(w_a)$, allowed to change word width.

NOT gates can be realised as XOR gates with constant word `1...1`, but are often special-cased to allows for more efficient low-level implementation.
The special-casing of XOR-CONST and AND-CONST gates allows for cheaper translation to the 3-party computation: the improvement is modest in the case of XOR-CONST over XOR, but significant in the case of AND-CONST over AND, because execution of the the AND gate in the MPCitH requires pseudo-random sampling and communication.

The secret initial state $x$ to the circuit is split into #defn[input shares] across the 3 simulated parties as follows, where $r^(0)$ and $r^(1)$ are words pseudo-randomly sampled from the secret seeds $s^(0)$ and $s^(1)$, respectively, of parties $0$ and $1$ in the 3-party computation:

$
  (r^(0), r^(1), (x xor r^(0) xor r^(1)))
$

Across the simulated 3-party computation, the word shares held by the three parties invariantly XOR to the corresponding word in the original circuit computation, but any subset of two shares is secured by sampled pseudo-randomness.
The simulated 3-party computation progresses as follows for each circuit gate:

#align(center)[
  #table(
    columns: (auto, auto),
    align: (left, left),
    stroke: none,
    column-gutter: 5mm,
    table.header("Circuit gate", "Simulated 3-party computation"),
    $w_b := not w_a$, $(w_b^0, w_b^1, w_b^2) := (not w_a^0, w_a^1, w_a^2)$,
    $w_c := w_a xor w_b$, $(w_c^0, w_c^1, w_c^2) := (w_a^0 xor w_b^0, w_a^1 xor w_b^1, w_a^2 xor w_b^2)$,
    $w_b := w_a xor k$, $(w_b^0, w_b^1, w_b^2) := (w_a^0 xor k, w_a^1, w_a^2)$,
    $w_c := w_a and w_b$, $w_c^(i) := (w_a^(i) and w_b^(i)) xor m_c^i "(see below)"$,
    $w_b := w_a and k$, $(w_b^0, w_b^1, w_b^2) := (w_a^0 and k, w_a^1 and k, w_a^2 and k)$,
    $w_b := phi(w_a)$, $(w_b^0, w_b^1, w_b^2) := (phi(w_a^0), phi(w_a^1), phi(w_a^2))$,
  )
]

With the exception of AND gates with two variable arguments, all gates can be implemented by operations local to each party.
In fact, MPC operations can be implemented in SIMD fashion, with the same operation applied to each party: the NOT and XOR-CONST formulations are merely an optimisation aimed at reducing the number of native NOT/XORs from three to one, because of cancellations.

The implementation of the AND gate $w_c = w_a and w_b$ is the only one requiring pseudo-random sampling and multi-party communication.
For each such gate, we pseudo-randomly sample words $(r_c^0, r_c^1, r_c^2)$ for the parties and define the following #defn[AND message], where $i$ ranges over $bb(Z)_3 := {0, 1, 2}$, with addition taken modulo 3:

$
  m_c^(i) := (w_a^(i) and w_b^(i+1)) xor (w_a^(i+1) and w_b^(i)) xor r_c^(i) xor r_c^(i+1)
$

For gates other than AND gates, it is trivial to check --- by induction over the circuit gates --- that XORing the resulting shares in the simulated 3-party computation yields the result of the original circuit computation.
#footnote[For the case of $w_b := phi(w_a)$, this follows from the requirement that $phi$ be XOR-affine.]
For the AND gates $w_c = w_a and w_b$, this can be demonstrated by direct calculation:

#[
  #show math.equation: set text(size: 8pt)
  $
    & xor.big_(i=0)^(3) ( (w_a^(i) and w_b^(i)) xor (w_a^(i) and w_b^(i+1)) xor (w_a^(i+1) and w_b^(i)) xor r_c^(i) xor r_c^(i+1) ) \
    = & xor.big_(i=0)^(3) ( (w_a^(i) and w_b^(i)) xor (w_a^(i) and w_b^(i+1))) xor xor.big_(i=0)^(3)(w_a^(i+1) and w_b^(i)) xor xor.big_(i=0)^(3)r_c^(i) xor xor.big_(i=0)^(3) r_c^(i+1) \
    = & xor.big_(i=0)^(3) ( (w_a^(i) and w_b^(i)) xor (w_a^(i) and w_b^(i+1))) xor xor.big_(i=0)^(3)(w_a^(i) and w_b^(i-1)) xor xor.big_(i=0)^(3)r_c^(i) xor xor.big_(i=0)^(3) r_c^(i) \
    = & xor.big_(i=0)^(3) ( (w_a^(i) and w_b^(i)) xor (w_a^(i) and w_b^(i+1)) xor (w_a^(i) and w_b^(i-1))) \
    = & xor.big_(i=0)^(3) xor.big_(j=0)^(3) (w_a^(i) and w_b^(j))
    = (xor.big_(i=0)^(3) w_a^i) and (xor.big_(j=0)^(3) w_b^j)
  $
]

At the end of the simulated 3-party computation, a hash commitment $H(underline(w)^i)$ is computed to the #defn[view] $underline(w)^i$ for each party $i in bb(Z)_3$.
The #defn[output share] $underline(y)^i := (w_o^i)_(o in O)$ for each party is recorded, where $O$ is the sequence of word indices constituting the output of the original circuit and $underline(y) = (w_o)_(o in O)$ is the (public) circuit output.
The #defn[AND message vector] $underline(m)^i := (m_c^i)_(c in A)$ for each party is also recorded, where $A$ is the sequence of word indices $c$ for the AND gates $w_c = w_a and w_b$ in the circuit.

== Proof Generation

The ZK proof generation process involves the execution of the MPCitH for a number $N_epsilon$ of independent repetitions, where $N_epsilon$ is related to the soundness error $epsilon$ by:

$
  N_epsilon := ceil((log_2(epsilon^(-1)))/(log_2(3)-1))
$

For convenience, we define $[N_epsilon] := {0, ..., N_epsilon -1}$.
At each repetition $n in [N_epsilon]$, a triple of (pseudo-)random values $(s_n^0, s_n^1, s_n^2)$ is generated for the parties and used to seed the pseudo-random generators (PRGs) from which random values are sampled for input sharding (write $r_n^i$) and AND messages (write $r_(n, c)^i$, for $c in A$); we refer to the values as #defn[view seeds] and to the PRGs they seed as #defn[view PRGs].
The 3-party computation is then simulated, producing views $underline(w)_n^i$, from which hash commitments $h_n^i := H(underline(w)_n^i)$ are computed and output shares $underline(y)_n^i$ are extracted.
At the end of all iterations, all hash commitments and output shares are hashed, producing the #defn[challenge entropy]:

$
  H(((h_n^i, underline(y)_n^i)_(i in bb(Z)_3))_(n in [N_epsilon]))
$

The challenge entropy is used to seed a #defn[challenge PRG], from which a sequence $(e_n)_(n in [N_epsilon])$ of #defn[challenges] $e_n in bb(Z)_3$ are sampled.
We refer to $e_n$ and $e_n+1$ as the #defn[opened parties] and to $e_n+2$ as the #defn[unopened party], where additions are taken modulo 3.
For each repetition $n in [N_epsilon]$, a #defn[response] $R_n$ is assembled to include the following information:

- the challenge value $e_n$;
- the seeds $s_n^(e_n)$ and $s_n^(e_n+1)$ for the opened parties;
- the AND message vector $underline(m)^(e_n+1)$ for the second opened party;
- the commitment $h_n^(e_n+2)$ for the unopened party;
- if $e_n in {1, 2}$, the input share $(x xor r_n^(0) xor r_n^(1))$ for party 2.

The ZKBoo proof is the vector $underline(R) := (R_n)_(n in [N_epsilon])$ of responses for all $N_epsilon$ repetitions.

== Proof Verification

The ZK proof verification process involves the re-execution of the MPCitH for each independent response included in the proof $underline(R)$.
The views of the opened parties for response $R_n$ are re-executed as follows:

- The revealed values $s_n^(e_n)$ and $s_n^(e_n+1)$ are used to seed the two view PRGs.
- For parties 0 and 1, the input shares are sampled from the view PRGs; if party 2 is replayed, the included input share $(x xor r_n^(0) xor r_n^(1))$ is used instead.
- The 2-party simulated computation is carried out, using the AND message vector $underline(m)^(e_n+1)$ for the second opened party to supply to the absence of messages from the unopened party.
- The view commitments and output shares for the opened parties are derived from the recomputed views.
- The view commitment for the unopened party is taken from the response.
- The output share $underline(y)^(e_n+2)$ for the unopened party is reconstructed from the known output $underline(y)$ and the output shares for the opened parties $underline(y)^(e_n)$ and $underline(y)^(e_n+1)$:
  $
    underline(y)^(e_n+2) = underline(y) xor underline(y)^(e_n) xor underline(y)^(e_n+1)
  $

This process is repeated for all responses, and challenge entropy is derived by hashing the resulting view commitments and output shares, as done by the proof generation process.
The sequence of challenges is pseudo-randomly derived from the challenge entropy and compared to the challenges included with the responses.
The proof is valid if all challenges agree.

#pagebreak()

= Implementation <sec:implementation>

== Computational Requirements

As already remarked in the previous section, the ZKBoo protocol can be straightforwardly extended from $"GF"(2)$ field operations to bitwise operations on arbitrary word types.
We make two additional observations concerning computational requirements of the MPCitH.

The first observation is that the implementation of MPCitH itself uses bitwise operation on the same word types as the original circuit and that, with the exception of AND gates, it uses the exact same bitwise operations as the original circuit, repeated on a per-party basis.
XOR-affine transformations, in particular, can be restricted to a subset suitable for direct low-level implementation, such as bit-shifts, bit-rotations, bit-reversal, byte-reversal, word widening (zero-extension), word narrowing (truncation), and constant insertion at native word widths.
The implementation of AND gates for each party uses an AND gate corresponding to that of the original circuit, plus an addition of two AND gates, four XOR gates, and two pseudo-random samples.

The second observation is that --- although not explicitly described in the ZKBoo circuit model --- wrapping addition on native word sizes can be implemented using a XOR gate, an AND gate, and a special-purpose CARRY gate applied to the resulting "propagate" and "generate" words. The CARRY gate is defined by a chain of single-bit XOR and AND operations, but grouped in such a way that it results in a single AND message at the relevant word width as far as the MPCitH is concerned. This makes it possible to implement circuits involving many common arithmetic operations with relatively minor overhead.

As a consequence, the computational requirements for the MPCitH performed by the ZKBoo prover and verifier can be made to fall within a reasonable constant factor of the computational requirements by the original circuit, assuming that pseudo-random sampling can be performed using hardware-accelerated primitives with a small amortised cost per sampled word (e.g. using AES counter mode).

== Memory Requirements

Computational requirements are relevant for applications with stringent time constraints, but are not the limiting factor for ZK implementations in secure elements: the real bottleneck are the memory requirements.
To set the scene for our subsequent remarks, we briefly survey some representative numbers from a reference SHA-256 implementation applied to a secret 64B input.

- The trace length for the execution is 8816 operations, with 8704 32-bit words and 112 8-bit words written to memory, for a total trace size of \~34KiB.
- A fully materialised circuit description, e.g. using a 4-bit op encoding with 14-bit absolute word indices, would result in 32-bit per gate, for a total of \~34KiB.
- Each view produces 2912 32-bit AND messages, for a total of \~11.4KiB. The additional 2x 32B seeds, 64B input share and 32B commitment digest only marginally increase the size to \~11.5KiB.
- At a 128-bit post-quantum security level, we need to set the soundness error to $epsilon = 2^(256)$, corresponding to $N_epsilon = 438$ iterations and an overall proof size of \~5MiB.

In context of a \~7.5KiB heap limit, the size of the AND messages alone would be enough to make the implementation for SHA-256 significantly challenging, and to completely rule out proofs for longer computations of practical interest.
We now make a number of observations which dramatically improve the situation, making memory requirements independent of trace length, security parameter, and the number of AND messages.

The first observation is that storing the entire computational trace is unnecessary: It suffices to allocate the minimum number of registers required to store the largest intermediate state in the computation, and to separately maintain a hasher for each party which ingests the output words as they are produced. For our SHA-256 example, it suffices to allocate space for 120 8-bit words and 99 32-bit words, for a total of 516B. The circuit state requirements for the prover's MPCitH then total to 1548B, since the internal states for the three hashers are hosted on the cryptography co-processor.

The second observation is that materialisation of the entire circuit is not necessary for the execution of the MPCitH: each gate applied by the three simulated parties corresponds exactly to a single gate in the original circuit, in the same sequence and without reference to topologically related gates.
As a consequence, ZKBoo circuits can be implemented as programs, with function calls, local state, and a memory manager taking care of allocating output words to free slots in the circuit state registers.
This includes the possibility of parametric circuit generation --- dependent on public information --- but excludes the case of fully dynamical circuit, which would need to be fully materialised.
The overhead from memory management consists of a list of refcounts --- in practical cases, an 8-bit counter per register will suffice --- and an allocation bitset: in the SHA-256 example, this amounts to an extra 299B for the whole MPCitH computation, accounting for a relatively marginal \~16% of the memory allocation.

The previous two observations remove any direct dependencies of memory on trace length.
The next two observations concerns the dependency on security parameter (determining the number of responses in a proof) and the number of AND messages (determining the length of each response).

One issue with the formulation of the ZKBoo protocol is that all view commitments and outputs shares must be computed before any challenge can be sampled.
In a naive implementation --- or in an implementation which aims to maximise time performance in the context of abundant memory --- the following data is stored for each repetition while challenge entropy is accumulated: the view commitments triple, the output share triple, the AND message vector and the input share for party 2.
This introduces a memory dependency on the product of the number of AND messages and the number of repetitions (a linear function of the security parameter). This amounts to \~1.5x the size of the proof, in the order of \~7.5MiB for our SHA-256 example.

The third observation, then, is that the memory requirements for the challenge entropy generation phase can be shrunk down to those of the MPCitH execution by making the view seed generation a pseudo-random process, based on a master secret and repeatable exactly in the subsequent response generation phase.
All we need to do in the challenge entropy generation phase is execute the MPCitH for each repetition and ingest the view commitment triple and output share triple into the challenge hasher, without storing any additional information.
In the response generation phase, we repeat the exact same executions with the exact same sequence of view seed triples, and we use knowledge of the challenge sample for each repetition to immediately generate the corresponding response.

The fourth and final observation concerns the memory requirements of the response generation itself.
It is a well-understood feature of ZKBoo and related protocols that proofs are streamable: each response is generated independently and can immediately be sent to the verifier, removing the dependency of memory on the security parameter.
However, it is interesting to observe that the AND messages of an individual response can themselves be streamed to the verifier, as soon as they are produced or in small batches.
This finally removes the dependency of memory on the number of AND messages, making it possible to execute ZKBoo protocols in memory within a small constant factor (slightly above 3x) of the intermediate state requirements for the original circuit.

== Implementation Summary

We now summarise the implementation of a ZKBoo prover within a secure element.

+ A #defn[master secret] is (pseudo-)randomly sampled and used to seed a #defn[master PRG].
+ A #defn[challenge hasher] is instantiated.
+ The #defn[challenge entropy generation] phase takes place. For each rep $n in [N_epsilon]$:
  + A triple of #defn[view seeds] is sampled from the master PRG.
  + A triple of #defn[view hashers] is initialised.
  + The MPCitH is executed, ingesting each output word produced by each party into the corresponding view hasher.
  + The view hashers are finalized, producing a triple of #defn[view commitments].
  + A triple of #defn[output shares] is extracted from the final state of the MPCitH.
  + The view commitments and output shares are ingested into the challenge hasher.
+ The challenge hasher is finalised, producing the #defn[challenge entropy].
+ The challenge entropy is used to seed the #defn[challenge PRG].
+ The master PRG is re-initialized from the master secret.
+ The verifier is notified that response streaming has started.
+ The #defn[response generation] phase takes place. For each rep $n in [N_epsilon]$:
  + A #defn[challenge] is sampled from the challenge PRG.
  + The challenge is sent to the verifier.
  + If required, the input share for party 2 is sent to the verifier.
  + A triple of view seeds is sampled from the master PRG.
  + The seeds for the two opened parties are sent to the verifier.
  + A triple of view hashers is initialised.
  + The MPCitH is executed:
    + Each output word produced by each party is ingested into the corresponding view hasher.
    + The AND message for the second opened party is sent to the verifier.
  + The view hashers are finalized, producing a triple of view commitments.
  + The view commitment for the unopened party is sent to the verifier.
+ The verifier is notified that the response streaming has ended.

Because it is based on essentially the same MPCitH as the prover --- with a vector of AND messages supplying the required information from the missing state shares for the unopened party --- the ZKBoo verifier can similarly be implemented with memory requirements proportional to circuit state requirements, with a smaller proportionality factor (slightly above 2x).

+ The verifier is notified that response streaming has started.
+ A challenge hasher is instantiated.
+ An empty #defn[challenges vector] is instantiated.#footnote[The memory for this vector is proportional to the security parameter, but packed at 2-bit per challenge the overhead is minor, in the order of 110B for 128-bit post-quantum security level.]
+ For each rep $n in [N_epsilon]$ in the response generation phase:
  + A triple of view hashers is initialised.
  + The verifier waits to receive the challenge.
  + The challenge is pushed into the challenge vector.
  + The verifier optionally waits to receive the input share for party 2.
  + The verifier waits to receive the view seeds for the two opened parties.
  + The three input shares are computed.
  + The MPCitH for the two opened parties is started:
    - Each output word produced by each party is ingested into the corresponding view hasher.
    - At each AND gate encountered, the verifier stops and waits for an AND message from the prover, and computation resumes once the message has been received.
  + The view hashers are finalized, producing two view commitments.
  + The output shares for all three parties are computed.
  + The view commitments and output shares are ingested into the challenge hasher.
+ The verifier is notified that the response streaming has ended.
+ The challenge hasher is finalised, producing the #defn[putative challenge entropy].
+ The challenge entropy is used to seed the #defn[putative challenge PRG].
+ A sequence of $N_epsilon$ #defn[putative challenges] is sampled from the putative challenge PRG and compared to the challenges in the challenge vector.
+ The verifier outputs success if all putative challenges coincide with the corresponding received challenges, and failure otherwise.

= Succinct Lifting <sec:succinct-lifting>

A known limitation of ZKBoo --- and one of the reasons why it doesn't hold much mindshare in the modern ZK landscape --- is that neither its proofs nor its verifier are succinct, in that both the size of the former and the runtime of the latter are linear in (a quantity typically proportional to) the trace length.
Verification can be performed with limited memory resources, but its lack of succinctness makes it unsuitable for applications, such as on-chain verification, where trace length for the verifier is a strict limiting factor.

At this point, we highlight how the purpose of ZKBoo is to extract information from a secure element with zero-knowledge guarantees, but that the proof it produces need not be used directly for verification.
Once the secret has been extracted, it can be sent to a more powerful machine for recursive verification, resulting in a succinct lifting of the proof: if the ZKBoo proof $pi$ proves the statement "I know $x$ such that $f(x) = y$" for a public circuit $f$ and output $y$, the lifted proof succinctly proves the statement "I known a ZKboo proof $pi$ for the statement that I know $x$ such that $f(x) = y$."

Importantly, the machine performing the succinct lifting does not need to be trusted, creating the opportunity for ecosystem economics or sponsorship.
Furthermore, the technique used for succinct lifting does not itself need to be zero-knowledge: that property is already provided by the ZKBoo proof, and the ZKBoo proof itself is not a secret.
This opens the door to applications of ZK systems based on binary fields, such as Binius @binius2023 @binius2024, which might be better suited to proving statements heavy in bitwise operations --- as the ZKBoo verifier computation is --- but might not yet be formulated in a zero-knowledge way.

#bibliography("biblio.bib")
