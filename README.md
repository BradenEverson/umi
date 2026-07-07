<img width="400" alt="image" src="https://github.com/user-attachments/assets/7974a35b-9d07-4e2c-a817-f7e43222e26c" />

*Shigeru Mizuki - Umibozu (1985)*

# umi - A language by me for me :D

I like a lot of languages. I like Rust's type system and pattern matching, I like Zig's philosophy and allocator/IO patterns, I like C's bitwise arithmetic even if it's not as explicit. Umi exists as a culmination of everything I like about everything I've worked in before. It's not a language killer, in fact I think I'll be the only one to ever use it :) Not only this, but it is also my first real attempt at a true full circle language and compiler project. I've done mini compiler components, interpreters, VMs, and hardware descriptions before, but this really is just throwing it all together! 


## Sample Program

This is my current vision for what writing umi would look like:

```
enum PacketCode(u8) {
    nop(0x00),
    left(0x01),
    right(0x02),
    angle(0x04),
}

struct Packet {
    code: PacketCode,
    payload: []u8,
}

fn main() -> void {
    let bytes: []u8 = {
        0x01,                  // Code: Left 
        0x00, 0x04,            // Len: 4 byte payload following
        0x00, 0x00, 0x00, 0x0F // Some payload
    };

    let packet = Packet::from_bytes(bytes);
}
```

I want this language for my specific low level projects I like to work on. These frequently require the construction of structs from a sequence of bytes. Hence this whole idea.

Essentially, every single struct and primative type define this `from_bytes` function. Slices of types define from bytes as first reading a u16 len, followed by calling `from_bytes` for `len` of the subtype. Pretty cool :)

Of course these require allocations, which borrows heavily from Zig's allocator design
