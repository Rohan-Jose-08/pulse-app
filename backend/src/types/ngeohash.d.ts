declare module 'ngeohash' {
  interface NeighborHashes {
    n: string; ne: string; e: string; se: string; s: string; sw: string; w: string; nw: string; }
  const ngeohash: {
    encode(lat:number,lng:number,precision?:number): string;
    decode(hash:string): { latitude:number; longitude:number; error?:number };
    decode_bbox(hash:string): [number, number, number, number];
    neighbors(hash:string): string[];
  };
  export default ngeohash;
}
