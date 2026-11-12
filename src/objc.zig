//! Objective-C runtime access without any Objective-C source: every call goes through objc_msgSend
//! cast to the method's C signature.

pub const id = ?*anyopaque;
pub const Class = ?*anyopaque;
pub const SEL = ?*anyopaque;

extern "objc" fn objc_getClass(name: [*:0]const u8) Class;
extern "objc" fn sel_registerName(name: [*:0]const u8) SEL;
extern "objc" fn objc_msgSend() void;
extern "objc" fn objc_autoreleasePoolPush() ?*anyopaque;
extern "objc" fn objc_autoreleasePoolPop(pool: ?*anyopaque) void;
extern "objc" fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Class;
extern "objc" fn objc_registerClassPair(cls: Class) void;
extern "objc" fn class_addMethod(cls: Class, name: SEL, imp: *const anyopaque, types: [*:0]const u8) bool;

pub const Rect = extern struct { x: f64, y: f64, w: f64, h: f64 };
pub const Point = extern struct { x: f64, y: f64 };
pub const Size = extern struct { w: f64, h: f64 };

/// Send `selector` to `target`. `Fn` is the method's C signature including receiver and selector.
pub fn send(comptime Fn: type, target: id, selector: [*:0]const u8, args: anytype) @typeInfo(Fn).@"fn".return_type.? {
    const f: *const Fn = @ptrCast(&objc_msgSend);
    return @call(.auto, f, .{ target, sel_registerName(selector) } ++ args);
}

pub fn sel(name: [*:0]const u8) SEL {
    return sel_registerName(name);
}

pub fn class(name: [*:0]const u8) id {
    return objc_getClass(name) orelse @panic("objc class not found");
}

pub fn new(class_name: [*:0]const u8) id {
    return send(fn (id, SEL) callconv(.c) id, alloc(class_name), "init", .{});
}

pub fn alloc(class_name: [*:0]const u8) id {
    return send(fn (id, SEL) callconv(.c) id, class(class_name), "alloc", .{});
}

pub fn release(obj: id) void {
    if (obj != null) send(fn (id, SEL) callconv(.c) void, obj, "release", .{});
}

pub fn retain(obj: id) id {
    return send(fn (id, SEL) callconv(.c) id, obj, "retain", .{});
}

pub fn nsString(utf8: [*:0]const u8) id {
    return send(fn (id, SEL, [*:0]const u8) callconv(.c) id, class("NSString"), "stringWithUTF8String:", .{utf8});
}

pub fn cString(ns: id) [*:0]const u8 {
    return send(fn (id, SEL) callconv(.c) [*:0]const u8, ns, "UTF8String", .{});
}

pub fn get(obj: id, selector: [*:0]const u8) id {
    return send(fn (id, SEL) callconv(.c) id, obj, selector, .{});
}

pub fn setObj(obj: id, selector: [*:0]const u8, v: id) void {
    send(fn (id, SEL, id) callconv(.c) void, obj, selector, .{v});
}

pub fn setU(obj: id, selector: [*:0]const u8, v: u64) void {
    send(fn (id, SEL, u64) callconv(.c) void, obj, selector, .{v});
}

pub fn setB(obj: id, selector: [*:0]const u8, v: bool) void {
    send(fn (id, SEL, bool) callconv(.c) void, obj, selector, .{v});
}

pub fn call(obj: id, selector: [*:0]const u8) void {
    send(fn (id, SEL) callconv(.c) void, obj, selector, .{});
}

pub fn poolPush() ?*anyopaque {
    return objc_autoreleasePoolPush();
}

pub fn poolPop(p: ?*anyopaque) void {
    objc_autoreleasePoolPop(p);
}

pub fn makeClass(superclass: [*:0]const u8, name: [*:0]const u8) Class {
    return objc_allocateClassPair(class(superclass), name, 0) orelse @panic("objc_allocateClassPair failed");
}

pub fn addMethod(cls: Class, selector: [*:0]const u8, imp: anytype, types: [*:0]const u8) void {
    if (!class_addMethod(cls, sel_registerName(selector), @ptrCast(imp), types)) @panic("class_addMethod failed");
}

pub fn registerClass(cls: Class) void {
    objc_registerClassPair(cls);
}
