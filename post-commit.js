function findDetailElement(element){
    elements = element.parentNode.childNodes
    var retVal = null
    for(var i=0; i < elements.length; i++){
        if (elements[i].className=='detail'){
            retVal = elements[i]
        }
    }
    return retVal
}

function toogleDetail( element )
{
	//window.alert(element)
	if (element.style.display == 'none'){
		element.style.display = 'block'
        }
	else{
		element.style.display = 'none'
        }
}

function showAll(){
	showHideToAllDetails('block')
}

function hideAll(){
	showHideToAllDetails('none')
}

function showHideToAllDetails(param){
	var elements = document.getElementsByName('detail')
	for (var i=0; i < elements.length; i++) {
            elements[i].style.display = param                 
	}
}