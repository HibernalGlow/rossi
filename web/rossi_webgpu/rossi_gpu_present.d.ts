/* tslint:disable */
/* eslint-disable */

export class RossiWebPresenter {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * 异步创建 Web 呈现器并绑定到页面指定的 `<canvas>`
     */
    static init(canvas_id: string, width: number, height: number): Promise<RossiWebPresenter>;
    /**
     * 呈现一页 RGBA 图像到 `<canvas>`
     */
    render_page(rgba_bytes: Uint8Array, src_width: number, src_height: number, force_anime4k: boolean): void;
    /**
     * 当视口或窗口尺寸变化时调整 Surface 尺寸
     */
    resize(width: number, height: number): void;
}

export function create_web_presenter(canvas_id: string, width: number, height: number): Promise<RossiWebPresenter>;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly __wbg_rossiwebpresenter_free: (a: number, b: number) => void;
    readonly create_web_presenter: (a: number, b: number, c: number, d: number) => any;
    readonly rossiwebpresenter_init: (a: number, b: number, c: number, d: number) => any;
    readonly rossiwebpresenter_render_page: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly rossiwebpresenter_resize: (a: number, b: number, c: number) => void;
    readonly wasm_bindgen__convert__closures_____invoke__hc371d0b204d16f0d: (a: number, b: number, c: any) => [number, number];
    readonly wasm_bindgen__convert__closures_____invoke__h65223d15a1c75d25: (a: number, b: number, c: any, d: any) => void;
    readonly wasm_bindgen__convert__closures_____invoke__h0ba109d98b06aec6: (a: number, b: number, c: any) => void;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_destroy_closure: (a: number, b: number) => void;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
