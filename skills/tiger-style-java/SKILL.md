---
name: tiger-style-java
description: |
  Apply Tiger Style safety, predictability, and performance guidelines to Java 21+ codebases.
  Enforces bounded limits, pre-allocations, sealed Result patterns, and explicit runtime validations.
---

# Tiger Style for Java

This skill guides the implementation of Java 21+ applications under the strict safety and performance standards of Tiger Style. It ensures zero technical debt, predictable memory consumption, robust defensive tripwires, and modern Data-Oriented Programming (DOP) structures.

## When to Use

Adhere to this skill when:
- Designing low-latency, high-throughput, or safety-critical backend systems in Java.
- Writing data processing pipelines, financial ledger transaction loops, or network-bound systems.
- Reviewing PRs or refactoring Java modules to guarantee robustness and deterministic execution.

---

## Rules of Engagement

### Rule 1: Bounded Everything (No Unbounded Queues, Loops, Recursion, or I/O)
- **Queues**: Never use unbounded queues (like `LinkedBlockingQueue` without capacity). Prefer `ArrayBlockingQueue` or ring-buffer architectures.
- **Collections**: Initialize collections (`ArrayList`, `HashMap`, `HashSet`) with a fixed, known capacity when the size is bounded.
- **Loops**: Every `while` loop or dynamic `for` loop must have a hard-coded maximum iteration limit (safety governor) to prevent infinite-loop lockups.
- **Recursion**: Unbounded recursion is the same lockup risk as an unbounded loop, aimed at the stack instead of the heap. Prefer iteration; where recursion is unavoidable, thread through and enforce an explicit depth counter with a hard-coded maximum.
- **I/O**: Every blocking network or disk call must carry an explicit deadline (e.g., a `Duration` passed to the client, or `Socket.setSoTimeout()`). Never call a blocking operation that can wait forever.

### Rule 2: Garbage-Free Critical Path (Static & Bounded Allocations)
- Inside performance-sensitive code or hot execution loops, do not allocate short-lived objects on the heap.
- Prefer primitive types (`long`, `double`, `int`) and native flat arrays instead of boxed wrapper classes (`Long`, `Double`, `Integer`) to prevent cache misses (pointer chasing) and object churn.
- Allocate direct byte buffers (`ByteBuffer.allocateDirect()`) or object pools **once**, at startup, into a static or thread-local field, then reuse that same instance on every call — never invoke `allocateDirect()` from inside the hot path itself.
- The generic `Result<S, F>` from Rule 3 forces boxing of primitive payloads (a `long` balance becomes a `Long`). On a genuine hot path, prefer a primitive-specialized result instead of the boxed generic form, e.g.:
```java
public sealed interface LongResult<F> {
    record Success<F>(long value) implements LongResult<F> {}
    record Failure<F>(F error) implements LongResult<F> {}
}
```

### Rule 3: Expected Failures are Data (The Result Pattern)
- Throwing exceptions is only allowed for **unrecoverable programmer errors** or **system failures** (e.g., database connection lost, thread interrupted, assertions broken).
- All expected business logic failures (e.g., `AccountNotFound`, `InsufficientFunds`, `InvalidPayload`) must return a sealed `Result` interface.

```java
public sealed interface Result<S, F> {
    record Success<S, F>(S value) implements Result<S, F> {}
    record Failure<S, F>(F error) implements Result<S, F> {}
}
```

### Rule 4: Data-Oriented Programming (DOP) & Exhaustive Matches
- Model all domain data carriers as immutable `record` types.
- Model domain choices and states using `sealed interface` hierarchies.
- Handle state transitions using exhaustive pattern-matching `switch` expressions. Avoid imperative `if (obj instanceof X)` blocks.

### Rule 5: Defense-In-Depth Explicit Runtime Validation
- Use Java `assert` blocks only for non-critical developer assumptions that can be stripped in production.
- Use explicit runtime guard clauses (e.g., `Objects.requireNonNull()`, `Preconditions.checkArgument()`, `Validate.isTrue()`) for invariants that must be enforced in production.
- Assert both the **positive space** (expected state) and the **negative space** (asserting that invalid states are unreachable, e.g., the `default -> throw new IllegalStateException()` branch in an exhaustive switch).

### Rule 6: Big-Endian Explicit Naming
- Variable and method names must flow from most-significant category to least-significant qualifier.
- Names representing physical quantities must explicitly state their units at the end of the name.
  - *Correct*: `balanceCents`, `timeoutMs`, `bufferCapacityBytes`, `requestCountMax`.
  - *Incorrect*: `int ms;`, `long t;`, `int maxRequests;`.
- Use standard Java camelCase for fields and methods, but preserve the Big-Endian sorting logic.

### Rule 7: Small, Reviewable Functions
- A method body must not exceed **70 lines**. If it does, extract named helper methods rather than growing the method.
- Keep a single level of abstraction per method: a method that orchestrates steps should call out to helpers, not mix orchestration with low-level detail.
- Limit nesting depth to **3 levels** (e.g., `if` inside `for` inside `if`). Prefer early returns and guard clauses over deep nesting.

### Rule 8: Overflow-Checked Arithmetic
- Never use raw `+`, `-`, `*` on `int`/`long` quantities that represent money, counts, or capacities — silent overflow corrupts state without a crash.
- Use `Math.addExact()`, `Math.subtractExact()`, `Math.multiplyExact()`, `Math.toIntExact()`, etc., so overflow throws `ArithmeticException` (a system failure per Rule 3) instead of wrapping silently.
- Prefer `long` over `int` for any accumulator that can grow with input size or over the lifetime of a process.

### Rule 9: Deterministic & Property-Based Testing
- Every negative-space assertion from Rule 5 (an "unreachable" state) must be exercised by a test that proves it is either truly unreachable or correctly rejected — an assertion nobody tests is a guess, not a guarantee.
- Prefer property-based tests (e.g., [jqwik](https://jqwik.net/)) over hand-picked example tests for validating invariants (e.g., "balance never goes negative") across a wide, randomized input space.
- Seed all randomized tests explicitly and log the seed on failure, so a failing case is deterministically reproducible.

---

## Code Templates & Idioms

### Bounded Buffer Loop Template
```java
public final class RingBufferProcessor {
    private static final int ITERATION_LIMIT = 10_000;
    private final ArrayBlockingQueue<Transaction> queue = new ArrayBlockingQueue<>(1024);

    public void drainAndProcess() {
        int processedCount = 0;
        Transaction tx;
        // Strict guard to prevent infinite lock-up
        while (processedCount < ITERATION_LIMIT && (tx = queue.poll()) != null) {
            processTransaction(tx);
            processedCount++;
        }

        // Only trip the governor if the limit stopped the loop AND work is still
        // pending. Reaching the limit exactly as the queue drains is not an overrun.
        if (processedCount >= ITERATION_LIMIT && !queue.isEmpty()) {
            throw new IllegalStateException("Safety governor limit hit: processed " + ITERATION_LIMIT + " txs");
        }
    }
}
```

### ArchUnit Architecture Verification
```java
@AnalyzeClasses(packages = "com.tigerstyle.demo", importOptions = ImportOption.DoNotIncludeTests.class)
public class TigerStyleArchTest {

    // Note: this only catches declared checked-exception `throws` clauses.
    // It cannot see unchecked exceptions thrown without being declared, so
    // pair it with a code review checklist item, not rely on it alone.
    @ArchTest
    public static final ArchRule no_thrown_business_exceptions =
        methods().that().arePublic().and().areDeclaredInClassesThat().haveSimpleNameEndingWith("Service")
        .should().notDeclareThrowableOfType(Throwable.class)
        .as("Public service methods must return Result types instead of throwing exceptions");

    private static final Set<String> UNIT_SUFFIXES =
        Set.of("Ms", "Ns", "Bytes", "Cents", "Max", "Min", "Count");

    private static final ArchCondition<JavaField> haveExplicitUnitsSuffix =
        new ArchCondition<>("have an explicit unit suffix") {
            @Override
            public void check(JavaField field, ConditionEvents events) {
                boolean isQuantitativePrimitive = field.getRawType().isEquivalentTo(long.class)
                    || field.getRawType().isEquivalentTo(int.class)
                    || field.getRawType().isEquivalentTo(double.class);
                if (!isQuantitativePrimitive) {
                    return;
                }
                boolean hasUnitSuffix = UNIT_SUFFIXES.stream().anyMatch(field.getName()::endsWith);
                events.add(new SimpleConditionEvent(field, hasUnitSuffix,
                    "Field " + field.getFullName() + " does not declare an explicit unit suffix"));
            }
        };

    @ArchTest
    public static final ArchRule numeric_fields_must_have_explicit_units =
        fields().should(haveExplicitUnitsSuffix)
        .as("All quantitative primitive numeric fields must specify explicit unit suffixes (e.g. balanceCents, timeoutMs)");
}
```

### Checkstyle Enforcement (Function Size & Nesting — Rule 7)
ArchUnit inspects compiled bytecode metadata, not source line counts or brace nesting, so line-length and nesting-depth limits belong in Checkstyle instead:
```xml
<module name="TreeWalker">
    <module name="MethodLength">
        <property name="max" value="70"/>
        <property name="countEmpty" value="false"/>
    </module>
    <module name="NestedIfDepth">
        <property name="max" value="3"/>
    </module>
    <module name="NestedForDepth">
        <property name="max" value="3"/>
    </module>
    <module name="NestedTryDepth">
        <property name="max" value="3"/>
    </module>
</module>
```

### Property-Based Invariant Test (Rule 9)
```java
class LedgerProperties {

    @Property
    void balanceNeverGoesNegative(@ForAll @LongRange(min = 0, max = 1_000_000) long openingBalanceCents,
                                   @ForAll @LongRange(min = 0, max = 1_000_000) long withdrawalCents) {
        LongResult<WithdrawalError> result = Ledger.withdraw(openingBalanceCents, withdrawalCents);

        switch (result) {
            case LongResult.Success<WithdrawalError> success ->
                assertThat(success.value()).isGreaterThanOrEqualTo(0L);
            case LongResult.Failure<WithdrawalError> failure ->
                assertThat(failure.error()).isEqualTo(WithdrawalError.INSUFFICIENT_FUNDS);
        }
    }
}
```
A failing case prints its seed in the jqwik report; rerun with `@Seed("<value>")` on the method to reproduce it deterministically.
