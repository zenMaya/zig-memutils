# zig-memutils
Memory utilities for the Zig programming language, including a reference counted pointer

This repository contains a few usable patterns for memory management
in Zig.

## Owner and Borrower

Owners and Borrowers allow you to specify the ownership of data
(usually a pointer or a structure with `deinit`). As in Zig there are
no in language semantics to make this clear. For example the
`std.StringHashMap` does not own its keys.

In Owner-Borrower memory model would signatures of some functions look
like this:
```zig
// instead of
fn put(self: *Self, key: []const u8, value: V) !void

// this
fn put(self: *Self, key: Borrower([]const u8), value: V) !void
```

To get most of the features of this model, one should always pair an
`Owner` instance with its respective `deinit()`

```zig
var owner: Owner(usize) = .{ .data = 0 };
defer owner.deinit();

some_fn_borrowing(owner.borrow());
some_fn_owning(owner.give());

// this is an error, as ownership was already transfered
// some_fn_owning(owner.give());
```

`Borrower` instances are only informative about the API, they do not
themselves need to be deinitialized and do not perform any checks
about their validity.

## Rc the reference counted pointer

Rc allows to hold multiple references to a place in memory when there
is no easy way to make sure that that memory isn't pointed to from
anywhere else. It's a very standard datastructure in many programming
languages. But this implementation provides a few interesting
properties.

Unless a slice is provided, one should pass the type that the memory
location should have __not the pointer to that memory!__

```zig
var rc = Rc(usize).init(0, std.testing.allocator);
defer rc.drop();
const raw_ptr: *usize = rc.get();
```

If the type has a `fn deinit(*T)` or a `fn deinit(*T,
std.mem.Allocator)` member function, the `Rc` will automatically call
this function before destroying it's memory location.

A custom deinit function can also be provided with `init_w_deinit_fn`,
and must have the `*const fn (*T, std.mem.Allocator)` type signature.

For a propper usage, `Rc` should never be "copy assigned", but that is
currently unenforcable in Zig.

```zig
var rc = Rc(usize).init(0, std.testing.allocator);
defer rc.drop();

// never do this
var rc2 = rc;
// instead do this
var rc3 = rc.borrow();
defer rc3.drop();
```

### Rc with a slice

If one wishes to use `Rc` with a slice, the semantics are a bit
different. The biggest difference is that `Rc` now expects the slice
as it's argument instead of the item's type.

```zig
var rc = Rc([]u8).init_dupe("string", std.testing.allocator);
defer rc.drop();

var rc2 = Rc([]u8).init(6, std.testing.allocator);
defer rc2.drop();
@memcpy(rc2.get(), "string");
```

Otherwise `Rc` behaves the same. However slices usually provide a way
to subslice, but simply doing `rc.get()[0..3]` would not increase the
reference count. For this `Rc` implements `fn subslice(from, to)`.

This does not copy memory, only creates a new `Rc` that still works
with the same memory location, will potentially free the whole memory
if no references to the memory exist, but returns a different slice when
calling `get`.

```zig
var rc = Rc([]u8).init_dupe("test", std.testing.allocator);
defer rc.drop();
var rc2 = rc.subslice(0, 3);
defer rc2.drop();
```

### Rc in multithreaded environments

Rc can be also used in multithreaded environments in a way that does
not introduce a cost in single threaded environments. To convert `Rc`
into an multithreading friendly one, simply call `fn atomic()`. The
type signature stays the same and all functions have the same
behavior, but `borrow` and `drop` are now thread-safe.

> Note that this operation can only be performed once.

```zig 
var rc = Rc(usize).init(0, std.testing.allocator);
defer rc.drop();
rc.atomic();
// from now on, rc is thread-safe, even the previous borrows
```
