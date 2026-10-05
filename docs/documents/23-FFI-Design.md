# PreviewX — FFI Design

## 1. Principle

FFI is optional, isolated, and justified by performance, parser maturity, or security.

## 2. Preferred Direction

```text
Swift
  ↓
C ABI
  ↓
Rust parser library
```

Avoid exposing Rust types directly across the ABI.

## 3. C ABI

```c
typedef struct {
    const uint8_t *data;
    size_t length;
} px_buffer;

typedef struct {
    int code;
    const char *message;
} px_result;

px_result px_parse_json(
    px_buffer input,
    px_buffer output
);
```

Ownership rules must be explicit.

## 4. Memory

- Caller owns input.
- Callee owns temporary parser state.
- Returned buffers have explicit free functions.
- No Swift object pointers cross the C ABI.

## 5. Error Mapping

```text
Rust error
  ↓
C error code
  ↓
Swift PXError
```

## 6. Threading

FFI functions must document thread safety.

## 7. When Not to Use FFI

Do not use Rust merely because it is available. A native Swift parser or library is preferred if it is sufficiently safe and fast.

## 8. Testing

Every FFI component needs:
- ABI test
- malformed input test
- memory test
- cancellation test where supported
- fuzzing
