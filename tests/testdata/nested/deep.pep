deep(items: int[]): int {
    var total = 0;
    for (var item in items) {
        if (item > 0 && item < 10) {
            total += item;
        }
    }
    return total;
}
