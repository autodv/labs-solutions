# AutoDV formal verification labs — reference solutions

Reference solutions for the labs at <https://autodv.github.io/labs/>. The
starter files are in [autodv/labs](https://github.com/autodv/labs).

Consult a lab's solution only after completing the lab, or when you are stuck.
Each folder holds the completed testbench or configuration and, where the lab
asks for a design fix (Labs 1, 3 and 4), the fixed design.

## verify.sh

`verify.sh` reruns every starter and solution configuration and every
experiment in the handouts (injected bugs, removed invariants, alternative
engines, EQY variants), and compares each result with what the handout states.
Use it to check that a different OSS CAD Suite release still behaves as
written. It needs the suite's `bin` directory on `PATH`.

```bash
git clone https://github.com/autodv/labs.git
git clone https://github.com/autodv/labs-solutions.git
labs-solutions/verify.sh labs        # uses the starter-v1 tag, not your edits
```

It runs in a temporary directory and takes about five minutes. Add `VERBOSE=1`
for more detail.

## License

The files in this repository are released under the [MIT License](LICENSE),
copyright (c) 2026 AutoDV. The lab handouts at <https://autodv.github.io/> are
licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
