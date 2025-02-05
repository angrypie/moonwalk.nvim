function topKSelect(arr: number[], k: number): number[] {
    if (k <= 0) return [];

    // Clone array to avoid mutating the original
    const clone = [...arr];
    const targetIndex = k - 1; // For k largest elements

    quickSelect(clone, 0, clone.length - 1, targetIndex);

    // Return first k elements (no sorting needed for basic top-K)
    return clone.slice(0, k);
}

function quickSelect(arr: number[], left: number, right: number, target: number): void {
    if (left >= right) return;

    const pivotIndex = partition(arr, left, right);

    if (pivotIndex === target) return;
    pivotIndex < target 
        ? quickSelect(arr, pivotIndex + 1, right, target)
        : quickSelect(arr, left, pivotIndex - 1, target);
}

function partition(arr: number[], left: number, right: number): number {
    const pivotValue = arr[right];
    let storeIndex = left;

    // Move larger elements to the left (descending order)
    for (let i = left; i < right; i++) {
        if (arr[i] > pivotValue) {
            [arr[i], arr[storeIndex]] = [arr[storeIndex], arr[i]];
            storeIndex++;
        }
    }

    // Place pivot in correct position
    [arr[right], arr[storeIndex]] = [arr[storeIndex], arr[right]];
    return storeIndex;
}

export function topK(data: number[], k: number): number[] {
	const topK = new Array(k).fill(-Infinity)
	const topKIndex = new Array(k).fill(-1)
	for (let i = 0; i < data.length; i++) {
		const value = data[i]
		if (value > topK[k - 1]) {
			let j = k - 1
			while (j > 0 && value > topK[j - 1]) {
				topK[j] = topK[j - 1]
				topKIndex[j] = topKIndex[j - 1]
				j--
			}
			topK[j] = value
			topKIndex[j] = i
		}
	}
	return topKIndex
}


//test speeed

function randomRangee(min: number, max: number) {
	return Math.floor(Math.random() * (max - min + 1)) + min;
}

function generateeRandomArray(size: number) {
	let array = new Array(size)
	for (let i = 0; i < size; i++) {
		array[i] = randomRangee(0, 5)
		if( i == 1000) {
			array.push(10000)
			array.push(100000)
			array.push(100000)
		}
		if(  i == 10000) {
			array.push(100000)
		}
		if(  i == 500000) { 
			array.push(90000)
		}
	}
	array.push(90000)
	return array
}

function test(fn: Function, size: number, name: string) {
	const array = generateeRandomArray(size)
	console.time(name)
	fn(array, 10)
	console.timeEnd(name)
}

console.log("TopK = 10")
test(topK, 100000000, "topK")
test(topKSelect, 10000000, "topKSelect")
