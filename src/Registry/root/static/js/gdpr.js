// Injects the GDPR notice onto sites
function createDataProtectionBanner() {
  var banner = document.createElement('div');
  var wrapper = document.createElement('div');
  var inner = document.createElement('div');

  // don't accidently create two banners
  if (document.getElementById("data-protection-banner") != null) {
    document.getElementById("data-protection-banner").remove();  
  }
  // status readout
  if (document.getElementById("data-protection-status") != null) {
    document.getElementById("data-protection-status").innerText += '\ncreating banner...';  
  }
 
  banner.id = "data-protection-banner";
  banner.className = "cookie-banner";
  wrapper.className = "row";
  wrapper.innerHTML = "" + 
    "<div class='alert alert-warning alert-fixed alert-dismissable content' role='alert'><strong>" +
    dataProtectionSettings.message +
    " To find out more, see our <a target='_blank' href='" + dataProtectionSettings.link + "'>privacy policy</a>.</br>" +
    "<a href='#' id='data-protection-agree'>Okay, dismiss this banner</a></strong></div>" +
    "";
   
  document.body.appendChild(banner);
  banner.appendChild(wrapper);

  openDataProtectionBanner();
}

function openDataProtectionBanner() {
  var height = document.getElementById('data-protection-banner').offsetHeight || 0;
  document.getElementById('data-protection-banner').style.display = 'block';
  document.body.style.paddingBottom = height+'px';

  document.getElementById('data-protection-agree').onclick = function() {
    closeDataProtectionBanner();
    return false;
  };
}

function closeDataProtectionBanner() {
  if (document.getElementById("data-protection-status") != null) {
    document.getElementById("data-protection-status").innerText += '\nclosing banner...';  
  }

  var height = document.getElementById('data-protection-banner').offsetHeight;
  document.getElementById('data-protection-banner').style.display = 'none';
  document.body.style.paddingBottom = '0';
  setCookie(dataProtectionSettings.cookieName, 'true', 90); 
}

function setCookie(c_name, value, exdays) {
  if (document.getElementById("data-protection-status") != null) {
    document.getElementById("data-protection-status").innerText += '\nsetting cookie for '+dataProtectionSettings.cookieName+' ...';  
  }
  
  var exdate = new Date();
  var c_value;
  exdate.setDate(exdate.getDate() + exdays);
  // c_value = escape(value) + ((exdays===null) ? "" : ";expires=" + exdate.toUTCString()) + ";domain=.ebi.ac.uk;path=/";
  // document.cookie = c_name + "=" + c_value;
  c_value = escape(value) + ((exdays===null) ? "" : ";expires=" + exdate.toUTCString()) + ";domain=" + document.domain + ";path=/";
  document.cookie = c_name + "=" + c_value;
}

function getCookie(c_name) {
  var i, x, y, ARRcookies=document.cookie.split(";");
  for (i=0; i<ARRcookies.length; i++) {
    x = ARRcookies[i].substr(0, ARRcookies[i].indexOf("="));
    y = ARRcookies[i].substr(ARRcookies[i].indexOf("=")+1);
    x = x.replace(/^\s+|\s+$/g,"");
    if (x===c_name) {
      return unescape(y);
    }
  }
}

var dataProtectionSettings = new Object();

function runDataProtectionBanner() {
  dataProtectionSettings.message = 'This website uses cookies. By continuing to browse this site, you are agreeing to the use of our site cookies. We also collect some limited personal information when you browse the site. You can find the details in our Privacy Policy.';
  dataProtectionSettings.link = 'http://www.ebi.ac.uk/data-protection/privacy-notice/trackhub-registry-anonymous-browsing';
  dataProtectionSettings.serviceId = 'ebi';
  dataProtectionSettings.dataProtectionVersion = '1.0';

  // If there's a div#data-protection-message-configuration, override defaults
  var divDataProtectionBanner = document.getElementById('data-protection-message-configuration');
  if (divDataProtectionBanner !== null) {
    if (typeof divDataProtectionBanner.dataset.message !== "undefined") {
      dataProtectionSettings.message = divDataProtectionBanner.dataset.message;
    }
    if (typeof divDataProtectionBanner.dataset.link !== "undefined") {
      dataProtectionSettings.link = divDataProtectionBanner.dataset.link;
    }
    if (typeof divDataProtectionBanner.dataset.serviceId !== "undefined") {
      dataProtectionSettings.serviceId = divDataProtectionBanner.dataset.serviceId;
    }
    if (typeof divDataProtectionBanner.dataset.dataProtectionVersion !== "undefined") {
      dataProtectionSettings.dataProtectionVersion = divDataProtectionBanner.dataset.dataProtectionVersion;
    }
  }
  
  dataProtectionSettings.cookieName = "trackhub-registry-anonymous-browsing";

  // If this version of banner not accepted, show it:
  if (getCookie(dataProtectionSettings.cookieName) != "true") {
    createDataProtectionBanner(); 
  } else {
    if (document.getElementById("data-protection-status") != null) {
      document.getElementById("data-protection-status").innerText += '\nbanner for '+dataProtectionSettings.cookieName+' previously accepted, I won\'t show it...';  
    }
  }

}

function resetDataProtectionBanner() {
  if (document.getElementById("data-protection-status") != null) {
    document.getElementById("data-protection-status").innerText += '\nresetting...';  
  }

  document.cookie = dataProtectionSettings.cookieName + "=; expires=Thu, 01 Jan 1970 00:00:00 GMT;domain=" + document.domain + ";path=/";

  runDataProtectionBanner();
}

if (document.getElementById("data-protection-status") != null) {
  document.getElementById("data-protection-status").innerText = '\nbootstrapping...';  
}

// execute
runDataProtectionBanner();

