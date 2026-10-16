class_name PlatformResourceLoaderInterface
extends Node
## Prepare existing package resources. Progress is work, not download percentage.
## Results retain strong resource references until the consumer releases them.

func prepare(_paths: PackedStringArray, owner: Node, generation: int,
		_type_hint: String = "Texture2D", _timeout_msec: int = 15000) -> PlatformResourceRequest:
	var request := PlatformResourceRequest.new(owner, generation)
	request._complete(PlatformResult.unsupported())
	return request
