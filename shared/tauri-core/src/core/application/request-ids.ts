/** One counter for every request this app sends, so no two lines in flight share an id. */
export class RequestIds {
  private last = 0;

  next(): number {
    this.last += 1;
    return this.last;
  }
}
