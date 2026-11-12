//! Direct3D 11, DXGI and the HLSL compiler, declared by hand: the structures and the COM interfaces the
//! renderer uses, laid out as in d3d11.h, dxgi1_2.h and d3dcompiler.h. An interface's function table lists
//! every slot in the header's order; the ones the game does not call are `Unused` placeholders, and
//! `expectSlot` pins each used one to its index at compile time.

const std = @import("std");
const w = @import("../platform/win32.zig");

const HRESULT = w.HRESULT;
const GUID = w.GUID;
const WINAPI = w.WINAPI;
const Unused = w.Unused;
const BOOL = w.BOOL;

// ---------------------------------------------------------------------------- constants

pub const sdk_version = 7;
pub const DRIVER_TYPE_HARDWARE = 1;
pub const DRIVER_TYPE_WARP = 5;
pub const FEATURE_LEVEL_11_0: u32 = 0xb000;
pub const CREATE_DEVICE_BGRA_SUPPORT = 0x20;

pub const FORMAT_UNKNOWN = 0;
pub const FORMAT_R16G16B16A16_FLOAT = 10;
pub const FORMAT_D32_FLOAT = 40;
pub const FORMAT_R32_UINT = 42;
pub const FORMAT_R8_UNORM = 61;
pub const FORMAT_B8G8R8A8_UNORM = 87;

pub const USAGE_DEFAULT = 0;
pub const USAGE_IMMUTABLE = 1;
pub const USAGE_DYNAMIC = 2;
pub const USAGE_STAGING = 3;
pub const BIND_INDEX_BUFFER = 0x2;
pub const BIND_CONSTANT_BUFFER = 0x4;
pub const BIND_SHADER_RESOURCE = 0x8;
pub const BIND_RENDER_TARGET = 0x20;
pub const BIND_DEPTH_STENCIL = 0x40;
pub const CPU_ACCESS_WRITE = 0x10000;
pub const CPU_ACCESS_READ = 0x20000;
pub const RESOURCE_MISC_GENERATE_MIPS = 0x1;
pub const RESOURCE_MISC_BUFFER_STRUCTURED = 0x40;
pub const MAP_READ = 1;
pub const MAP_WRITE_DISCARD = 4;
pub const SRV_DIMENSION_BUFFER = 1;
pub const FILTER_MIN_MAG_MIP_LINEAR = 0x15;
pub const TEXTURE_ADDRESS_CLAMP = 3;
pub const COMPARISON_NEVER = 1;
pub const COMPARISON_LESS_EQUAL = 4;
pub const COMPARISON_ALWAYS = 8;
pub const FILL_SOLID = 3;
pub const CULL_NONE = 1;
pub const DEPTH_WRITE_MASK_ZERO = 0;
pub const DEPTH_WRITE_MASK_ALL = 1;
pub const STENCIL_OP_KEEP = 1;
pub const BLEND_ZERO = 1;
pub const BLEND_ONE = 2;
pub const BLEND_SRC_ALPHA = 5;
pub const BLEND_INV_SRC_ALPHA = 6;
pub const BLEND_OP_ADD = 1;
pub const COLOR_WRITE_ENABLE_ALL = 0x0F;
pub const PRIMITIVE_TOPOLOGY_TRIANGLELIST = 4;
pub const CLEAR_DEPTH = 0x1;

pub const DXGI_USAGE_RENDER_TARGET_OUTPUT = 0x20;
pub const DXGI_SCALING_STRETCH = 0;
pub const DXGI_SWAP_EFFECT_FLIP_DISCARD = 4;
pub const DXGI_ALPHA_MODE_IGNORE = 3;
pub const DXGI_MWA_NO_ALT_ENTER = 0x2;
pub const DXGI_STATUS_OCCLUDED = w.hresult(0x087a0001);
pub const DXGI_ERROR_DEVICE_REMOVED = w.hresult(0x887A0005);
pub const DXGI_ERROR_DEVICE_RESET = w.hresult(0x887A0007);

pub const D3DCOMPILE_OPTIMIZATION_LEVEL3 = 1 << 15;

pub const IID_IDXGIDevice = GUID.parse("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
pub const IID_IDXGIFactory2 = GUID.parse("50c83a1c-e072-4c48-87b0-3630fa36a6d0");
pub const IID_ID3D11Texture2D = GUID.parse("6f15aaf2-d208-4e89-9ab4-489535d34f9c");

// ---------------------------------------------------------------------------- structures

pub const SAMPLE_DESC = extern struct { Count: u32 = 1, Quality: u32 = 0 };

pub const BUFFER_DESC = extern struct {
    ByteWidth: u32,
    Usage: u32,
    BindFlags: u32,
    CPUAccessFlags: u32 = 0,
    MiscFlags: u32 = 0,
    StructureByteStride: u32 = 0,
};

pub const SUBRESOURCE_DATA = extern struct {
    pSysMem: ?*const anyopaque,
    SysMemPitch: u32 = 0,
    SysMemSlicePitch: u32 = 0,
};

pub const TEXTURE2D_DESC = extern struct {
    Width: u32,
    Height: u32,
    MipLevels: u32 = 1,
    ArraySize: u32 = 1,
    Format: u32,
    SampleDesc: SAMPLE_DESC = .{},
    Usage: u32 = USAGE_DEFAULT,
    BindFlags: u32,
    CPUAccessFlags: u32 = 0,
    MiscFlags: u32 = 0,
};

/// D3D11_SHADER_RESOURCE_VIEW_DESC with the union spelled as its buffer member; the largest member is
/// four UINTs.
pub const SHADER_RESOURCE_VIEW_DESC = extern struct {
    Format: u32 = FORMAT_UNKNOWN,
    ViewDimension: u32,
    FirstElement: u32 = 0,
    NumElements: u32 = 0,
    reserved: [2]u32 = .{ 0, 0 },
};

pub const SAMPLER_DESC = extern struct {
    Filter: u32,
    AddressU: u32,
    AddressV: u32,
    AddressW: u32,
    MipLODBias: f32 = 0,
    MaxAnisotropy: u32 = 1,
    ComparisonFunc: u32 = COMPARISON_NEVER,
    BorderColor: [4]f32 = .{ 0, 0, 0, 0 },
    MinLOD: f32 = 0,
    MaxLOD: f32 = std.math.floatMax(f32),
};

pub const RASTERIZER_DESC = extern struct {
    FillMode: u32 = FILL_SOLID,
    CullMode: u32 = CULL_NONE,
    FrontCounterClockwise: BOOL = 0,
    DepthBias: i32 = 0,
    DepthBiasClamp: f32 = 0,
    SlopeScaledDepthBias: f32 = 0,
    DepthClipEnable: BOOL = 1,
    ScissorEnable: BOOL = 0,
    MultisampleEnable: BOOL = 0,
    AntialiasedLineEnable: BOOL = 0,
};

pub const DEPTH_STENCILOP_DESC = extern struct {
    StencilFailOp: u32 = STENCIL_OP_KEEP,
    StencilDepthFailOp: u32 = STENCIL_OP_KEEP,
    StencilPassOp: u32 = STENCIL_OP_KEEP,
    StencilFunc: u32 = COMPARISON_ALWAYS,
};

pub const DEPTH_STENCIL_DESC = extern struct {
    DepthEnable: BOOL,
    DepthWriteMask: u32,
    DepthFunc: u32,
    StencilEnable: BOOL = 0,
    StencilReadMask: u8 = 0xFF,
    StencilWriteMask: u8 = 0xFF,
    FrontFace: DEPTH_STENCILOP_DESC = .{},
    BackFace: DEPTH_STENCILOP_DESC = .{},
};

pub const RENDER_TARGET_BLEND_DESC = extern struct {
    BlendEnable: BOOL = 0,
    SrcBlend: u32 = BLEND_ONE,
    DestBlend: u32 = BLEND_ZERO,
    BlendOp: u32 = BLEND_OP_ADD,
    SrcBlendAlpha: u32 = BLEND_ONE,
    DestBlendAlpha: u32 = BLEND_ZERO,
    BlendOpAlpha: u32 = BLEND_OP_ADD,
    RenderTargetWriteMask: u8 = COLOR_WRITE_ENABLE_ALL,
};

pub const BLEND_DESC = extern struct {
    AlphaToCoverageEnable: BOOL = 0,
    IndependentBlendEnable: BOOL = 0,
    RenderTarget: [8]RENDER_TARGET_BLEND_DESC = @splat(.{}),
};

pub const VIEWPORT = extern struct {
    TopLeftX: f32 = 0,
    TopLeftY: f32 = 0,
    Width: f32,
    Height: f32,
    MinDepth: f32,
    MaxDepth: f32,
};

pub const MAPPED_SUBRESOURCE = extern struct {
    pData: ?*anyopaque = null,
    RowPitch: u32 = 0,
    DepthPitch: u32 = 0,
};

pub const SWAP_CHAIN_DESC1 = extern struct {
    Width: u32,
    Height: u32,
    Format: u32,
    Stereo: BOOL = 0,
    SampleDesc: SAMPLE_DESC = .{},
    BufferUsage: u32,
    BufferCount: u32,
    Scaling: u32,
    SwapEffect: u32,
    AlphaMode: u32,
    Flags: u32 = 0,
};

pub const ADAPTER_DESC = extern struct {
    Description: [128]u16,
    VendorId: u32,
    DeviceId: u32,
    SubSysId: u32,
    Revision: u32,
    DedicatedVideoMemory: usize,
    DedicatedSystemMemory: usize,
    SharedSystemMemory: usize,
    AdapterLuid: extern struct { LowPart: u32, HighPart: i32 },
};

comptime {
    std.debug.assert(@sizeOf(BUFFER_DESC) == 24);
    std.debug.assert(@sizeOf(SUBRESOURCE_DATA) == 16);
    std.debug.assert(@sizeOf(TEXTURE2D_DESC) == 44);
    std.debug.assert(@sizeOf(SHADER_RESOURCE_VIEW_DESC) == 24);
    std.debug.assert(@sizeOf(SAMPLER_DESC) == 52);
    std.debug.assert(@sizeOf(RASTERIZER_DESC) == 40);
    std.debug.assert(@sizeOf(DEPTH_STENCIL_DESC) == 52);
    std.debug.assert(@sizeOf(RENDER_TARGET_BLEND_DESC) == 32);
    std.debug.assert(@sizeOf(BLEND_DESC) == 264);
    std.debug.assert(@sizeOf(VIEWPORT) == 24);
    std.debug.assert(@sizeOf(MAPPED_SUBRESOURCE) == 16);
    std.debug.assert(@sizeOf(SWAP_CHAIN_DESC1) == 48);
    std.debug.assert(@sizeOf(ADAPTER_DESC) == 304);
}

// ---------------------------------------------------------------------------- interfaces

/// Objects the renderer only holds and hands back: each is released through `w.Com.release`.
pub const Resource = opaque {};
pub const Buffer = opaque {};
pub const Texture2D = opaque {};
pub const ShaderResourceView = opaque {};
pub const RenderTargetView = opaque {};
pub const DepthStencilView = opaque {};
pub const VertexShader = opaque {};
pub const PixelShader = opaque {};
pub const BlendState = opaque {};
pub const DepthStencilState = opaque {};
pub const RasterizerState = opaque {};
pub const SamplerState = opaque {};

pub const Device = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        CreateBuffer: *const fn (*Device, *const BUFFER_DESC, ?*const SUBRESOURCE_DATA, *?*Buffer) callconv(WINAPI) HRESULT,
        CreateTexture1D: Unused,
        CreateTexture2D: *const fn (*Device, *const TEXTURE2D_DESC, ?[*]const SUBRESOURCE_DATA, *?*Texture2D) callconv(WINAPI) HRESULT,
        CreateTexture3D: Unused,
        CreateShaderResourceView: *const fn (*Device, *anyopaque, ?*const SHADER_RESOURCE_VIEW_DESC, *?*ShaderResourceView) callconv(WINAPI) HRESULT,
        CreateUnorderedAccessView: Unused,
        CreateRenderTargetView: *const fn (*Device, *anyopaque, ?*const anyopaque, *?*RenderTargetView) callconv(WINAPI) HRESULT,
        CreateDepthStencilView: *const fn (*Device, *anyopaque, ?*const anyopaque, *?*DepthStencilView) callconv(WINAPI) HRESULT,
        CreateInputLayout: Unused,
        CreateVertexShader: *const fn (*Device, *const anyopaque, usize, ?*anyopaque, *?*VertexShader) callconv(WINAPI) HRESULT,
        CreateGeometryShader: Unused,
        CreateGeometryShaderWithStreamOutput: Unused,
        CreatePixelShader: *const fn (*Device, *const anyopaque, usize, ?*anyopaque, *?*PixelShader) callconv(WINAPI) HRESULT,
        CreateHullShader: Unused,
        CreateDomainShader: Unused,
        CreateComputeShader: Unused,
        CreateClassLinkage: Unused,
        CreateBlendState: *const fn (*Device, *const BLEND_DESC, *?*BlendState) callconv(WINAPI) HRESULT,
        CreateDepthStencilState: *const fn (*Device, *const DEPTH_STENCIL_DESC, *?*DepthStencilState) callconv(WINAPI) HRESULT,
        CreateRasterizerState: *const fn (*Device, *const RASTERIZER_DESC, *?*RasterizerState) callconv(WINAPI) HRESULT,
        CreateSamplerState: *const fn (*Device, *const SAMPLER_DESC, *?*SamplerState) callconv(WINAPI) HRESULT,
        CreateQuery: Unused,
        CreatePredicate: Unused,
        CreateCounter: Unused,
        CreateDeferredContext: Unused,
        OpenSharedResource: Unused,
        CheckFormatSupport: Unused,
        CheckMultisampleQualityLevels: *const fn (*Device, u32, u32, *u32) callconv(WINAPI) HRESULT,
        CheckCounterInfo: Unused,
        CheckCounter: Unused,
        CheckFeatureSupport: Unused,
        GetPrivateData: Unused,
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetFeatureLevel: Unused,
        GetCreationFlags: Unused,
        GetDeviceRemovedReason: *const fn (*Device) callconv(WINAPI) HRESULT,
        GetImmediateContext: Unused,
        SetExceptionMode: Unused,
        GetExceptionMode: Unused,
    };
};

pub const Context = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        GetDevice: Unused,
        GetPrivateData: Unused,
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        VSSetConstantBuffers: *const fn (*Context, u32, u32, [*]const ?*Buffer) callconv(WINAPI) void,
        PSSetShaderResources: *const fn (*Context, u32, u32, [*]const ?*ShaderResourceView) callconv(WINAPI) void,
        PSSetShader: *const fn (*Context, ?*PixelShader, ?*anyopaque, u32) callconv(WINAPI) void,
        PSSetSamplers: *const fn (*Context, u32, u32, [*]const ?*SamplerState) callconv(WINAPI) void,
        VSSetShader: *const fn (*Context, ?*VertexShader, ?*anyopaque, u32) callconv(WINAPI) void,
        DrawIndexed: Unused,
        Draw: *const fn (*Context, u32, u32) callconv(WINAPI) void,
        Map: *const fn (*Context, *anyopaque, u32, u32, u32, *MAPPED_SUBRESOURCE) callconv(WINAPI) HRESULT,
        Unmap: *const fn (*Context, *anyopaque, u32) callconv(WINAPI) void,
        PSSetConstantBuffers: *const fn (*Context, u32, u32, [*]const ?*Buffer) callconv(WINAPI) void,
        IASetInputLayout: *const fn (*Context, ?*anyopaque) callconv(WINAPI) void,
        IASetVertexBuffers: Unused,
        IASetIndexBuffer: *const fn (*Context, ?*Buffer, u32, u32) callconv(WINAPI) void,
        DrawIndexedInstanced: *const fn (*Context, u32, u32, u32, i32, u32) callconv(WINAPI) void,
        DrawInstanced: *const fn (*Context, u32, u32, u32, u32) callconv(WINAPI) void,
        GSSetConstantBuffers: Unused,
        GSSetShader: Unused,
        IASetPrimitiveTopology: *const fn (*Context, u32) callconv(WINAPI) void,
        VSSetShaderResources: *const fn (*Context, u32, u32, [*]const ?*ShaderResourceView) callconv(WINAPI) void,
        VSSetSamplers: Unused,
        Begin: Unused,
        End: Unused,
        GetData: Unused,
        SetPredication: Unused,
        GSSetShaderResources: Unused,
        GSSetSamplers: Unused,
        OMSetRenderTargets: *const fn (*Context, u32, ?[*]const ?*RenderTargetView, ?*DepthStencilView) callconv(WINAPI) void,
        OMSetRenderTargetsAndUnorderedAccessViews: Unused,
        OMSetBlendState: *const fn (*Context, ?*BlendState, ?*const [4]f32, u32) callconv(WINAPI) void,
        OMSetDepthStencilState: *const fn (*Context, ?*DepthStencilState, u32) callconv(WINAPI) void,
        SOSetTargets: Unused,
        DrawAuto: Unused,
        DrawIndexedInstancedIndirect: Unused,
        DrawInstancedIndirect: Unused,
        Dispatch: Unused,
        DispatchIndirect: Unused,
        RSSetState: *const fn (*Context, ?*RasterizerState) callconv(WINAPI) void,
        RSSetViewports: *const fn (*Context, u32, [*]const VIEWPORT) callconv(WINAPI) void,
        RSSetScissorRects: Unused,
        CopySubresourceRegion: Unused,
        CopyResource: *const fn (*Context, *anyopaque, *anyopaque) callconv(WINAPI) void,
        UpdateSubresource: *const fn (*Context, *anyopaque, u32, ?*const anyopaque, *const anyopaque, u32, u32) callconv(WINAPI) void,
        CopyStructureCount: Unused,
        ClearRenderTargetView: *const fn (*Context, *RenderTargetView, *const [4]f32) callconv(WINAPI) void,
        ClearUnorderedAccessViewUint: Unused,
        ClearUnorderedAccessViewFloat: Unused,
        ClearDepthStencilView: *const fn (*Context, *DepthStencilView, u32, f32, u8) callconv(WINAPI) void,
        GenerateMips: *const fn (*Context, *ShaderResourceView) callconv(WINAPI) void,
        SetResourceMinLOD: Unused,
        GetResourceMinLOD: Unused,
        ResolveSubresource: *const fn (*Context, *anyopaque, u32, *anyopaque, u32, u32) callconv(WINAPI) void,
        ExecuteCommandList: Unused,
        /// Slots 59 to 109: the hull, domain and compute stages and every getter.
        stages_and_getters: [51]Unused,
        ClearState: *const fn (*Context) callconv(WINAPI) void,
        Flush: *const fn (*Context) callconv(WINAPI) void,
        GetType: Unused,
        GetContextFlags: Unused,
        FinishCommandList: Unused,
    };
};

pub const SwapChain = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetPrivateData: Unused,
        GetParent: Unused,
        GetDevice: Unused,
        Present: *const fn (*SwapChain, u32, u32) callconv(WINAPI) HRESULT,
        GetBuffer: *const fn (*SwapChain, u32, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        SetFullscreenState: Unused,
        GetFullscreenState: Unused,
        GetDesc: Unused,
        ResizeBuffers: *const fn (*SwapChain, u32, u32, u32, u32, u32) callconv(WINAPI) HRESULT,
    };
};

pub const Factory2 = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetPrivateData: Unused,
        GetParent: Unused,
        EnumAdapters: Unused,
        MakeWindowAssociation: *const fn (*Factory2, w.HWND, u32) callconv(WINAPI) HRESULT,
        GetWindowAssociation: Unused,
        CreateSwapChain: Unused,
        CreateSoftwareAdapter: Unused,
        EnumAdapters1: Unused,
        IsCurrent: Unused,
        IsWindowedStereoEnabled: Unused,
        CreateSwapChainForHwnd: *const fn (*Factory2, *anyopaque, w.HWND, *const SWAP_CHAIN_DESC1, ?*const anyopaque, ?*anyopaque, *?*SwapChain) callconv(WINAPI) HRESULT,
    };
};

pub const DxgiDevice = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetPrivateData: Unused,
        GetParent: Unused,
        GetAdapter: *const fn (*DxgiDevice, *?*Adapter) callconv(WINAPI) HRESULT,
    };
};

pub const Adapter = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetPrivateData: Unused,
        GetParent: *const fn (*Adapter, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        EnumOutputs: Unused,
        GetDesc: *const fn (*Adapter, *ADAPTER_DESC) callconv(WINAPI) HRESULT,
    };
};

pub const Blob = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: w.Com.VTable,
        GetBufferPointer: *const fn (*Blob) callconv(WINAPI) ?*anyopaque,
        GetBufferSize: *const fn (*Blob) callconv(WINAPI) usize,
    };

    pub fn bytes(b: *Blob) []const u8 {
        const p: [*]const u8 = @ptrCast(b.vtbl.GetBufferPointer(b) orelse return &.{});
        return p[0..b.vtbl.GetBufferSize(b)];
    }
};

comptime {
    // Slot numbers from the Vtbl structs in the headers (IUnknown is 0 to 2).
    const D = Device.VTable;
    w.expectSlot(D, "CreateBuffer", 3);
    w.expectSlot(D, "CreateTexture2D", 5);
    w.expectSlot(D, "CreateShaderResourceView", 7);
    w.expectSlot(D, "CreateRenderTargetView", 9);
    w.expectSlot(D, "CreateDepthStencilView", 10);
    w.expectSlot(D, "CreateVertexShader", 12);
    w.expectSlot(D, "CreatePixelShader", 15);
    w.expectSlot(D, "CreateBlendState", 20);
    w.expectSlot(D, "CreateDepthStencilState", 21);
    w.expectSlot(D, "CreateRasterizerState", 22);
    w.expectSlot(D, "CreateSamplerState", 23);
    w.expectSlot(D, "CheckMultisampleQualityLevels", 30);
    w.expectSlot(D, "GetDeviceRemovedReason", 39);
    std.debug.assert(@sizeOf(D) == 43 * @sizeOf(usize));
    const C = Context.VTable;
    w.expectSlot(C, "VSSetConstantBuffers", 7);
    w.expectSlot(C, "PSSetShaderResources", 8);
    w.expectSlot(C, "PSSetShader", 9);
    w.expectSlot(C, "PSSetSamplers", 10);
    w.expectSlot(C, "VSSetShader", 11);
    w.expectSlot(C, "Draw", 13);
    w.expectSlot(C, "Map", 14);
    w.expectSlot(C, "Unmap", 15);
    w.expectSlot(C, "PSSetConstantBuffers", 16);
    w.expectSlot(C, "IASetInputLayout", 17);
    w.expectSlot(C, "IASetIndexBuffer", 19);
    w.expectSlot(C, "DrawIndexedInstanced", 20);
    w.expectSlot(C, "DrawInstanced", 21);
    w.expectSlot(C, "IASetPrimitiveTopology", 24);
    w.expectSlot(C, "VSSetShaderResources", 25);
    w.expectSlot(C, "OMSetRenderTargets", 33);
    w.expectSlot(C, "OMSetBlendState", 35);
    w.expectSlot(C, "OMSetDepthStencilState", 36);
    w.expectSlot(C, "RSSetState", 43);
    w.expectSlot(C, "RSSetViewports", 44);
    w.expectSlot(C, "CopyResource", 47);
    w.expectSlot(C, "UpdateSubresource", 48);
    w.expectSlot(C, "ClearRenderTargetView", 50);
    w.expectSlot(C, "ClearDepthStencilView", 53);
    w.expectSlot(C, "GenerateMips", 54);
    w.expectSlot(C, "ResolveSubresource", 57);
    w.expectSlot(C, "ClearState", 110);
    w.expectSlot(C, "Flush", 111);
    std.debug.assert(@sizeOf(C) == 115 * @sizeOf(usize));
    w.expectSlot(SwapChain.VTable, "Present", 8);
    w.expectSlot(SwapChain.VTable, "GetBuffer", 9);
    w.expectSlot(SwapChain.VTable, "ResizeBuffers", 13);
    w.expectSlot(Factory2.VTable, "MakeWindowAssociation", 8);
    w.expectSlot(Factory2.VTable, "CreateSwapChainForHwnd", 15);
    w.expectSlot(DxgiDevice.VTable, "GetAdapter", 7);
    w.expectSlot(Adapter.VTable, "GetParent", 6);
    w.expectSlot(Adapter.VTable, "GetDesc", 8);
    w.expectSlot(Blob.VTable, "GetBufferPointer", 3);
    w.expectSlot(Blob.VTable, "GetBufferSize", 4);
}

pub extern "d3d11" fn D3D11CreateDevice(
    adapter: ?*anyopaque,
    driver_type: u32,
    software: w.HINSTANCE,
    flags: u32,
    feature_levels: ?[*]const u32,
    feature_level_count: u32,
    sdk: u32,
    device: *?*Device,
    feature_level: ?*u32,
    context: *?*Context,
) callconv(WINAPI) HRESULT;

/// D3DCompile, from d3dcompiler_47.dll.
pub const CompileFn = *const fn (
    src: [*]const u8,
    src_len: usize,
    source_name: ?[*:0]const u8,
    defines: ?*const anyopaque,
    include: ?*anyopaque,
    entry: [*:0]const u8,
    target: [*:0]const u8,
    flags1: u32,
    flags2: u32,
    code: *?*Blob,
    errors: *?*Blob,
) callconv(WINAPI) HRESULT;

test {
    // Referencing the tables runs the layout checks above on whatever machine runs the tests.
    _ = Device.VTable;
    _ = Context.VTable;
    _ = SwapChain.VTable;
    _ = Factory2.VTable;
    _ = BLEND_DESC;
}
