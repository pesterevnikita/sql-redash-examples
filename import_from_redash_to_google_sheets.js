//доп менюшка для запуска скрипта из меню вверху

function onOpen (){
    var spreadsheet = SpreadsheetApp.getActive();
    var menuItems = [
    {name: 'assessment', functionName: 'importTasks_by_A_fromRedash'}
  ];
  spreadsheet.addMenu('Solver', menuItems);
  
  }


function importTasksfromRedash() {
  //достаём цсв из базы, чтобы в гуглтаблицах работать удобнее

  var csvUrl = "https://redash.skyeng.ru/api/queries/69/results.csv?api_key=bWQp7pqhHBjew2HfxGqpdAaOSYBFuoYj6sE4j";
  var csvContent = UrlFetchApp.fetch(csvUrl).getContentText();
  var csvData = Utilities.parseCsv(csvContent); 
    
    function deleteRow(arr, row) {
    arr = arr.slice(0); // make copy of csv input
    arr.splice(row - 1, 1);
    return arr;    
    }

  
  var sheet = SpreadsheetApp.openById('1jsKN1ce1xRYPoFLUx-yBMZQDFT0GZRGagtrj_1U').getSheetByName('Count_answered_tasks');
  sheet.getRange(2, 1, sheet.getLastRow(), 28).clear({contentsOnly:true});
  var Avals = sheet.getRange("A1:A").getValues();
  var Alast = Avals.filter(String).length;
  var nothing = false  


  if (csvData.length == 1) {nothing = true}
   else {
  sheet.getRange(Alast+1, 1, csvData.length-1, csvData[0].length).setValues(deleteRow(csvData, 1));
     nothing = false;
  }

}
//аналогичная для другого отдела
   //работает автоматом каждый день в 3:00
  function importTasks_by_A_fromRedash() {     
  
    var csvUrl = "https://redash.skyeng.ru/api/queries/9/results.csv?api_key=qrlaV6ITghhsDlyPxqpVFPrk3qsPsB5mKiK";
    var csvContent = UrlFetchApp.fetch(csvUrl).getContentText();
    var csvData = Utilities.parseCsv(csvContent);
      
    var ldate=csvData[1][0];  //дата из первой строки редаша

    function filterResults1(item) { //фильтруем старые строки до даты редаша
      if (item[0]!=""){ 
      var d1=ldate;
      var d2=Utilities.formatDate(item[0],"GMT+4","yyyy-MM-dd 00:00:00");
     //Logger.log(d1+":<?:"+(d1<d2)+":<?:"+d2);
      return (d2 < d1);
      } else return false;

    }
      
    var sheet = SpreadsheetApp.openById('1U2faMN0KL-4_R_u4b4H62ah3u7tDhL6BwGbfv4').getSheetByName('Stats');

    var nov_dan0=sheet.getRange(2, 1, sheet.getLastRow(), csvData[0].length).getValues();

    var nov_dan=nov_dan0.filter(filterResults1).concat(deleteRow(csvData, 1));

    sheet.getRange(2, 1, sheet.getLastRow(), csvData[0].length).clear({contentsOnly:true});
    var kol=nov_dan.length;
    var nothing = false;  

    if (kol == 1) {
      nothing = true;
    } else {
      sheet.getRange(2, 1, kol, csvData[0].length).setValues(nov_dan);
      nothing = false;
    }    
  }
